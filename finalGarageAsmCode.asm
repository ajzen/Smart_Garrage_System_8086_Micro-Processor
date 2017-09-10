.model tiny 
.8086          
.data

	strlen db 0
	empty db 'EMPTY'
	full db 'FULL'
	count dw 0

;assigning port addresses
    inadd_word equ 00h
    lcd_data equ 02h
    lcd_motor_control equ 04h
    creg_io equ 06h
    
    timer_clock equ 08h
    timer_remote equ 0ah
    timer_door equ 0ch
    creg_timer equ 0eh
	
    timer_clock2 equ 10h
    timer_remote2 equ 12h
    timer_door2 equ 14h
    creg_timer2 equ 16h
    
    jmp st1
    db 1024 dup(0)

.code
.startup
      
st1:

    mov cx, 0000h
    mov bx, 0000h
    mov dx, 0000h
     

inits:

    mov ax,0200h
    mov ds,ax
    mov es,ax
    mov ss,ax
    mov sp,0FFFEH 

    mov al,10000000b
    out creg_io,al   

    mov al, 00110110b
    out creg_timer, al
    mov al, 0A8h  ;10101000
    out timer_clock, al  ;Timer 1 intialize
    mov al, 61h   ;01100001
    out timer_clock, al         

   mov al,00110011b       ;Timer 2 intialize
   out creg_timer2,al

   call lcd_init
   call lcd_update

garageclosed:
    in al, inadd_word
    and al, 00000001b
    cmp al, 1
    je opendoor 
    jmp garageclosed

garageopen:
    mov cl,0
    mov ah, 0                   ; reset car flag to 0     
    in  al, inadd_word
	mov bl, al       
    and bl, 00000001b
    cmp bl, 00000001b           ; check for remote press      
    je closedoor
    mov bl, al       
    and bl, 00010000b
    cmp bl, 00010000b           ; check for timeout (5 minutes)
    je closedoor
    mov bl, al       
    and bl, 00000010b
    cmp bl, 00000010b           ; check for outer IR
    je entering    
    mov bl, al       
    and bl, 00001000b
    cmp bl, 00001000b           ; check for inner IR
    je exiting    
    jmp garageopen    
    
closedoor:
    call motor_clockwise
    call motor_start 
    call start_door_timer
    stillclosing:
        in al, inadd_word
        and al, 00100000b
        cmp al, 00100000b       ; wait for door to close completely
        jne stillclosing 
        
    call motor_stop
    jmp garageclosed

opendoor:
    call start_remote_timer
    call motor_anticlockwise     
    call motor_start 
    call start_door_timer
	
    stillopening:
        in al, inadd_word
        and al, 00100000b
        cmp al, 00100000b       ; wait for door to open completely
        jne stillopening
        
    call motor_stop
    jmp garageopen

entering:
    mov cl,0       
    in al, inadd_word
    mov bl, al       
    and bl, 00000001b
    cmp bl, 00000001b                 
    je closedoor
    mov bl,al	
    and bl, 00010000b
    cmp bl, 00010000b           ; check for timeout (5 minutes)
    je closedoor
    mov bl, al       
    and bl, 00000100b
    cmp bl, 00000100b           ; check for car
    jne nc00
    mov ah, 1
    nc00:    
        mov bl, al       
        and bl, 00001000b
        cmp bl, 00001000b       ; check for inner IR
        jne entering
    cmp ah, 1
    jne nc01
    inc count            
    call lcd_update
    nc01: 
        in al, inadd_word
        mov bl, al       
        and bl, 00001000b
        cmp bl, 00001000b       ; debounce
        je nc01
    jmp garageopen

exiting:  
    mov cl,0     
    in  al, inadd_word
    mov bl, al
    mov bl, al       
    and bl, 00000001b
    cmp bl, 00000001b                
    je closedoor
	
    and bl, 00010000b
    cmp bl, 00010000b           ; check for timeout (5 minutes)
    je closedoor
	
    mov bl, al       
    and bl, 00000100b
    cmp bl, 00000100b           ; check for car
    jne nc10
	
    mov ah, 1
    nc10:    
    mov bl, al       
        and bl, 00000010b
        cmp bl, 00000010b       ; check for outer IR
        jne exiting
    cmp ah, 1
    jne nc11
    dec count 
	
    call lcd_update
    nc11:        
        in al, inadd_word
        mov bl, al       
        and bl, 00000010b
        cmp bl, 00000010b       ; debounce
        je nc11
    jmp garageopen


lcd_init proc near
    mov al, 00001111b
    out lcd_data, al 
    mov bl, 00100000b       
    call setlcdmode
    mov bl, 00000000b        
    call setlcdmode
    ret
lcd_init endp

lcd_update proc near
    call lcd_clear
    mov al, ' '
    call lcd_add_lcd
    cmp count, 0
    jnz notempty
    lea di, empty
    mov strlen, 5 
    jmp loaded
    notempty:
        cmp count, 2000
        jnz notfull
        lea di, full
        mov strlen, 4
        jmp loaded
        notfull:
    		call lcd_bcd
            ret
	loaded:
       	call lcd_add_word
    ret
lcd_update endp

	lcd_bcd proc near
        mov ax, count
        mov cx, 0

        converting:   
            mov bl, 10
            div bl
            add ah, '0'
            mov bl, ah
            mov bh, 0
            push bx   
            inc cx
            mov ah, 0
            cmp ax, 0
            jne converting

        printing:
            pop ax
            call lcd_add_lcd
            loop printing
        ret
    lcd_bcd endp

    lcd_add_word proc near
    	mov cl, strlen

    	putting:
        	mov al, [di]
        	call lcd_add_lcd
        	inc di
        	loop putting
        ret
    lcd_add_word endp

    lcd_add_lcd proc near 
        push ax
        out lcd_data,al
        mov bl,10100000b        
        call setlcdmode
        mov bl,10000000b         
        call setlcdmode
        pop ax
        ret
    lcd_add_lcd endp

    lcd_clear proc near
        mov al, 00000001b
        out lcd_data, al
        mov bl,00100000b        
        call setlcdmode
        mov bl,00000000b        
        call setlcdmode
        ret
    lcd_clear endp


    setlcdmode proc near
        in al, lcd_motor_control
        and al, 00011111b
        or al, bl
        out lcd_motor_control, al
        ret
    setlcdmode endp

    start_door_timer proc near
        mov al, 10110000b
        out creg_timer, al  
        mov al, 90h
        out timer_door, al
        mov al, 01h
        out timer_door, al      
        ret
    start_door_timer endp

    start_remote_timer proc near
        mov al, 01110000b
        out creg_timer, al
        mov al, 30h
        out timer_remote, al
        mov al, 75h
        out timer_remote, al      
        ret
    start_remote_timer endp

    motor_stop proc near
        in al, lcd_motor_control
        and al, 11111100b  
        or al, 00000000b
        out lcd_motor_control, al       
        ret
    motor_stop endp

    motor_anticlockwise proc near
        in al, lcd_motor_control
        and al, 11111100b  
        or al, 00000001b
        out lcd_motor_control, al
        ret       
    motor_anticlockwise endp

    motor_clockwise proc near
        in al, lcd_motor_control
        and al, 11111100b  
        or al, 00000010b
        out lcd_motor_control, al       
        ret
    motor_clockwise endp

    motor_start proc near
       	in al,0cah
       	out timer_clock2,al
       	in al,08h
       	out timer_clock2,al
       	in al,0d4h
       	out timer_clock2,al
       	in al,30h
       	out timer_clock2,al
        ret
    motor_start endp

.exit
end

