.486
data  segment use16	
buf_sect db  512 dup(0) ; буфер для считываемых секторов

text  db 0dh,0ah,'Oshibka schitivaniya sectora!$'
text1 db 0dh,0ah,'Vvedite put k failu v formate 8.3, ispolzuyte tolko bolshie bukvi diska: $'
text2 db 0dh,0ah,'Zadayte kolichestvo bait: $'
text3 db 0dh,0ah,'Vi mozhete umenshit fail na ukazannoe kolichestvo bait: $',0dh,0ah
text4 db 0dh,0ah,'Takogo cataloga ili takogo faila net! $'
text5 db 0dh,0ah,'Vi ne mozhete umenshit fail! $'
text6 db 0dh,0ah,'Razmer faila uspeshno umenshen! $'
text7 db 0dh,0ah,'Oshibka zapisi sectora! $'
text8 db 0dh,0ah,'Oshibka, vi vveli nedopustimoe kolichestvo bait! $'
;область для записи пути к файлу
buf_str db 127
        db ?
        db 127 dup(?)
;область для записи числа байтов
buf_numb db 7
         db ?
         db 7 dup(?)
;буфер для перевода кластеров в сектора
arfmtc_buf_lw dw 0
arfmtc_buf_hg dw 0
size_file dd 0 ;размер файла
clstr_sctr db ? ;количество секторов в кластере
root_bgn dw 0 ; сектор начала корневого каталога
nmbr_dsk db 0 ;номер логического диска
size_root dw 0;размер корневого каталога
;10-байтная область параметров 
param  dd 0          ; номер начального сектора 
       dw 1           ; количество считываемых секторов 
       dw buf_sect        ; внутрисегментное смещение области данных
       dw data      ; значение указателя сегмента
end_of_bound_excptn dw 0 ;смещение последнего элемента буфера секторов
bgn_buf_sect dw 0 ;начало буфера считываемых секторов
clstrs_bgn dw 0; номер начального кластера
copy_ip dw 0;регистра ip до вызова процедуры search_root
offst_size_file dw 0;смещение поля о размере файла
buf_str_es db 125 dup(?)
data  ends
code segment use16
        assume ds: data, cs:code
m1:     mov ax, data
        mov ds, ax
        mov es, ax 
        
        lea si, ds:buf_sect
        add si, 511
        mov word ptr end_of_bound_excptn, si       
        ;ввод пути к файлу
        lea dx, ds:text1
        call output_str        
        lea dx,ds:buf_str
        call input_str
         ;перешлём строку
        lea di, es:buf_str_es
        lea si, ds:buf_str
        inc si
        movzx cx, byte ptr ds:[si]
        inc si
        rep movsb

        ;определение номера логического диска
        lea si,ds:buf_str
        call select_disk
        ;считывание первого сектора логического диска        
	call read_sect

        ;пересылаем значения количества секторов в кластере, количества заразервированных секторов и размера фат таблицы и вычисляем сектор корневого каталога
        lea si, ds:buf_sect
        mov al, byte ptr ds:[si+13]
        mov byte ptr ds:clstr_sctr, al
        mov cx, word ptr ds:[si+14] ;количество зарезервированных секторов
        movzx bx, byte ptr ds:[si+16] ;количество фат-таблиц
        mov ax, word ptr ds:[si+17]
        mov word ptr ds:size_root, ax;размер корневого каталога в записях
        mov ax, ds:[si+22]; размер фат таблицы
        mul bx
        add ax,cx
        mov word ptr ds:root_bgn, ax

        ;посчитаем размер корневого каталога в секторах и перешлём в память
        shr word ptr ds:size_root, 4

        ;изменим байты в области параметров и считаем сектор  
        mov ax, word ptr ds:root_bgn
        cwde ;расширим ax до eax           
        call chng_prmtr
        mov al, byte ptr ds:nmbr_dsk
        call read_sect

        ;входные данные для процедуры search_root для корневого каталога
        lea di, es:buf_str_es        
        add di, 3
        movzx eax, word ptr ds:root_bgn
        mov bx, word ptr ds:size_root ;количество итераций, соответствующее количеству секторов в корневом каталоге
        ;найдём запись о каталоге/файле
        cycle2: 
        lea si, ds:buf_sect
        call search_root
        inc di                     
        cmp byte ptr ds:[si], 10h ;проверим, каталог это или файл
        jnz short end_cycle2           
        mov ax, word ptr ds:[si+15] ;смещение о номере начального кластера
        mov word ptr ds:clstrs_bgn, ax       
        sub ax, 2
        movzx cx, byte ptr ds:clstr_sctr
        mul cx 
        mov ds:arfmtc_buf_lw, ax
        mov ds:arfmtc_buf_hg, dx
        mov eax, dword ptr ds: arfmtc_buf_lw
        movzx ecx, word ptr ds:root_bgn
        add eax, ecx       
        movzx ecx, word ptr ds:size_root
        add eax, ecx
        call chng_prmtr
        mov al, byte ptr ds:nmbr_dsk
        call read_sect
        movzx bx, ds:clstr_sctr ;количество итераций, соответствующее считыванию одного кластера
        jmp short cycle2
        end_cycle2:add si, 17                ;перешлём размер файла и сохраним смещение
        mov word ptr ds:offst_size_file, si
        mov ecx, dword ptr ds:[si] 
        mov dword ptr ds:size_file, ecx       
        lea dx, ds:text3
        call output_str
        
        ;узнаем, на какое количество байт можно уменьшить файл и выведем на экран
        mov eax,0
        movzx cx, byte ptr ds:clstr_sctr
        shl cx,9
        mov ax, word ptr ds:size_file  ;размер файла младшее слово
        lea si, ds:size_file
        mov dx, word ptr ds:[si+2]  ;размер файла старшее слово
        div cx
        cmp dx, 0
        jnz short empt
        lea dx,ds:text8 
        call output_str
        lea dx,ds:text5 
        call output_str
        jmp short exit
        empt:
        jmp short empt_down
        error_size:    
        push dx
        lea dx, ds:text3
        call output_str
        pop dx
        empt_down:
        mov ax,dx
        push dx
        cwde
        call out_int
        lea dx, ds:text2 ;приглашение к вводу количества байт
        call output_str
        lea dx, ds:buf_numb
        call input_str
       
        ;переведём ASCII-символы в число
        lea si, ds:buf_numb
        inc si
        inc si
        call cnvrsn_numb 
        pop dx 
        cmp ax, dx
        ja short error_size
        cwde   
        mov ecx, dword ptr ds:ds:size_file
        sub ecx, eax
        lea si, ds:buf_sect
        add si, word ptr ds:offst_size_file
        mov dword ptr ds:[si], ecx
        mov al, byte ptr ds:nmbr_dsk
        call write_sect       
        lea dx, ds:text6
        call output_str

exit:	mov ah, 4ch         ; завершение программы
	int  21h

;сообщение об ошибке чтения сектора
error:	lea  dx, ds: text
        call output_str
	jmp short exit

;сообщение об ошибке записи сектора
error_write: lea dx, ds:text7
             call output_str
             jmp short exit


;сообщение об отсутсвии каталога
error_nocat: lea dx, ds:text4
             call output_str
             jmp short exit

;процедура для вывода строк на экран, dx-адрес строки
output_str proc
mov ah,9
int 21h
ret
output_str endp

;процедура для перевода введённого с клавиатуры числа, ax-число на выходе
cnvrsn_numb proc 
    xor ax,ax
    mov bx,10  ; основание сc
ii2:
    mov cl,ds:si ; берем символ из буфера
    cmp cl,0dh  ; проверяем не последний ли он
    jz endin
     
    sub cl,'0' ; делаем из символа число 
    mul bx     ; умножаем на 10
    add ax,cx  ; прибавляем к остальным
    inc si     ; указатель на следующий символ
    jmp short ii2     ; повторяем

; все символы из буфера обработаны число находится в ax
endin:
    ret
cnvrsn_numb endp

;процедура для ввода строки, dx-адрес области ввода
input_str proc
mov ah, 0ah
int 21h
ret
input_str endp

;процедура считываниия сектора, al-номер логического диска
read_sect proc
mov cx, 0ffffh
lea bx, param     ; смещение области параметров 
int 25h                      ;чтение секторов в область buf
pop dx
jc short error
ret
read_sect endp

;процедра записи сектора, al-номер логического диска
write_sect proc
mov cx, 0ffffh
lea bx, param     ; смещение области параметров 
int 26h                      ;чтение секторов в область buf
pop dx
jc short error_write
ret
write_sect endp

;процедура для определения номера логического диска по букве, si-адрес начала строки, al-номер диска на выходе
select_disk proc
mov ah, byte ptr ds:[si+2]
sub ah, 41h
mov al, ah
mov byte ptr ds:nmbr_dsk, al
ret
select_disk endp

;di-адрес области строки символов, si-адрес буфера секторов, bx-количество итераций цикла
search_root proc
pop word ptr ds:copy_ip
mov word ptr ds:bgn_buf_sect,si
ex1:push si
push di
mov cx, 11 ;количество символов в строке
repe cmpsb
je short equal_ ;переход, если строки равны
pop di
pop si
add si,16
cmp si, word ptr ds:end_of_bound_excptn 
ja short ex
jmp short ex1
ex:
inc eax
call chng_prmtr
mov al, ds:nmbr_dsk
mov si, word ptr ds:bgn_buf_sect
push bx
call read_sect
mov cx,11
pop bx
dec bx
cmp bx, 0
jz error_nocat
jmp short ex1
equal_: push word ptr ds:copy_ip
ret
search_root endp

;процедура вывода hex-кодов в десятичном виде, eax-входные данные
out_int proc  	
	xor ecx,ecx	;счетчик десятичных цифр
	mov ebx,10	;основание сист. счисления
ckl:
	xor edx,edx	;расширим делимое
	div ebx
	push edx	;получаемые цифры кладем в стек
	inc cx
	test eax,eax	;делитель - ноль ?
	jnz ckl		;еще нет, продолжим

outpt:			;вывод числа на экран

	pop eax
	add al,'0'	;десятичную цифру -> в ASCII
	int 29h		;вывод цифры
	
	loop outpt
    
    ret
 
out_int endp 

;процедура изменения номера сектора в области параметров, входные данные-номер сектора в регистре eax
chng_prmtr proc
lea si, ds:param
mov dword ptr ds:[si], eax
ret
chng_prmtr endp
code  ends
end  m1

