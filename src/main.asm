; =====================================================================
;  SIMON DICE - v3.0
;  Lenguaje: Ensamblador Intel 8086
;  Entorno:  EMU8086 (modelo EXE, .model small)
; =====================================================================
;
;  CORRECCIONES RESPECTO A v2.0
;
;  BUG 7 (CRITICO - CRASH):
;    print_num usaba CX como contador de digitos con "inc cx", pero
;    nunca lo inicializaba a 0. Si CX tenia cualquier valor distinto
;    de cero al entrar (lo que puede ocurrir si INT 21h o INT 10h
;    modifican CX internamente, como sucede en EMU8086), el bucle
;    pn_imprimir intentaba sacar mas elementos del stack de los que
;    se habian apilado. Resultado: se pisaban los registros guardados
;    y la direccion de retorno, el programa saltaba a basura y se
;    colgaba sin mostrar ningun mensaje de error.
;    CORRECCION: xor cx, cx justo despues de los cuatro push iniciales.
;
; =====================================================================
;  INTERRUPCIONES UTILIZADAS:
;    INT 10h / AH=06h  -> limpiar pantalla
;    INT 10h / AH=02h  -> posicionar cursor
;    INT 10h / AH=0Eh  -> imprimir caracter (teletype)
;    INT 16h / AH=00h  -> leer tecla del teclado (bloqueante)
;    INT 1Ah / AH=00h  -> leer timer del sistema
;    INT 21h / AH=09h  -> imprimir cadena terminada en '$'
;    INT 21h / AH=02h  -> imprimir un caracter (BEL)
;    INT 21h / AH=4Ch  -> terminar programa
;
;  TECLAS DEL JUEGO:
;    [1]=A  [2]=B  [3]=C  [4]=D   [ENTER]=confirmar
;
;  PARA COMPILAR EN EMU8086:
;    1. File -> New -> "EXE Template"
;    2. Borrar el contenido del template y pegar este codigo
;    3. Assembler -> Assemble (F5) -- debe mostrar "0 Errors"
;    4. Run -> Run (F9) para ejecutar
; =====================================================================

.model small
.stack 200h

; =====================================================================
; SEGMENTO DE DATOS
; =====================================================================
.data

MAX_SEQ  equ 50

; --- Mensajes del juego -----------------------------------------------

msg_titulo  db '=========================================',13,10
            db '        S I M O N   D I C E             ',13,10
            db '    El clasico juego de memoria          ',13,10
            db '          -- 2 Jugadores --              ',13,10
            db '=========================================',13,10,'$'

msg_reglas  db 13,10
            db '  Como se juega:',13,10
            db '  --------------',13,10
            db '  La pantalla te va a mostrar una secuencia',13,10
            db '  de letras. Tu trabajo es repetirla exacta.',13,10
            db '  Cada ronda se agrega una letra nueva.',13,10
            db '  Si te equivocas, quedas eliminado.',13,10
            db '  Gana quien aguante mas rondas!',13,10
            db 13,10
            db '  Teclas que vas a usar:',13,10
            db '    [1]  ->  A',13,10
            db '    [2]  ->  B',13,10
            db '    [3]  ->  C',13,10
            db '    [4]  ->  D',13,10,'$'

msg_enter   db 13,10,'  Cuando esten listos, aprieten ENTER...','$'

msg_sep     db '  -----------------------------------------',13,10,'$'

msg_j1hdr   db 13,10
            db '  +---------------------------------------+',13,10
            db '  |         -- TURNO JUGADOR 1 --         |',13,10
            db '  +---------------------------------------+',13,10,'$'

msg_j2hdr   db 13,10
            db '  +---------------------------------------+',13,10
            db '  |         -- TURNO JUGADOR 2 --         |',13,10
            db '  +---------------------------------------+',13,10,'$'

msg_nivel   db '  Ronda        : ','$'
msg_pj1     db '  Jugador 1    : ','$'
msg_pj2     db '  Jugador 2    : ','$'
msg_pts_s   db ' pts',13,10,'$'
msg_crlf    db 13,10,'$'

msg_mira    db 13,10,'  Mira bien la secuencia:',13,10,'  > ','$'

msg_listo   db 13,10,13,10
            db '  Ya memorizaste? Apreta ENTER cuando estes listo...','$'

msg_repite  db 13,10,'  Ahora repeti la secuencia: ','$'

msg_bien    db 13,10,'  Bien hecho! Eso estuvo perfecto!',13,10,'$'
msg_mal     db 13,10,'  Uy... eso no era. Te equivocaste!',13,10,'$'

msg_elim1   db '  Jugador 1 queda eliminado. Suerte la proxima!',13,10,'$'
msg_elim2   db '  Jugador 2 queda eliminado. Suerte la proxima!',13,10,'$'
msg_j1elim  db '  (el jugador 1 ya fue eliminado)',13,10,'$'
msg_j2elim  db '  (el jugador 2 ya fue eliminado)',13,10,'$'

msg_maxniv  db 13,10
            db '  Increible! Llegaron al nivel maximo (50 rondas)!',13,10
            db '  Tienen una memoria de elefante, en serio.',13,10,'$'

msg_fin     db 13,10
            db '  =========================================',13,10
            db '          Y eso es todo, gente!            ',13,10
            db '  =========================================',13,10,'$'

msg_res1    db '  Jugador 1 llego hasta : ','$'
msg_res2    db '  Jugador 2 llego hasta : ','$'
msg_res_pt  db ' rondas',13,10,'$'

msg_gana1   db 13,10,'  El ganador es... el Jugador 1! Felicitaciones!',13,10,'$'
msg_gana2   db 13,10,'  El ganador es... el Jugador 2! Felicitaciones!',13,10,'$'
msg_empate  db 13,10,'  Empate total! Los dos llegaron igual de lejos.',13,10,'$'

msg_bye     db 13,10,'  Gracias por jugar, espero que se hayan divertido.',13,10
            db '  Hasta la proxima!',13,10,13,10,'$'

; --- Variables del juego ----------------------------------------------

secuencia   db MAX_SEQ dup(0)

long_seq    dw 0
rand_seed   dw 0ABCDh
puntaje1    dw 0
puntaje2    dw 0
vivo1       db 1
vivo2       db 1

mapa_sim    db 'A','B','C','D'

; =====================================================================
; SEGMENTO DE CODIGO
; =====================================================================
.code

; ---------------------------------------------------------------------
; MAIN
; ---------------------------------------------------------------------
main proc

    mov ax, @data
    mov ds, ax

    call clear_screen
    mov dx, offset msg_titulo
    call print_string
    mov dx, offset msg_reglas
    call print_string
    mov dx, offset msg_enter
    call print_string
    call wait_enter

    ; Semilla con el timer del sistema
    xor ax, ax
    int 1Ah
    or  dx, dx
    jnz seed_ok
    or  cx, cx
    jz  seed_fallback
    mov dx, cx
    jmp seed_ok
seed_fallback:
    mov dx, 0F3A7h
seed_ok:
    mov [rand_seed], dx

    mov word ptr [long_seq],  0
    mov word ptr [puntaje1],  0
    mov word ptr [puntaje2],  0
    mov byte ptr [vivo1], 1
    mov byte ptr [vivo2], 1

; =====================================================================
; BUCLE PRINCIPAL
; =====================================================================
game_loop:

    mov al, [vivo1]
    or  al, [vivo2]
    jz  end_game

    mov ax, [long_seq]
    cmp ax, MAX_SEQ
    jae nivel_maximo

    ; Agregar nuevo simbolo a la secuencia
    inc word ptr [long_seq]
    mov bx, [long_seq]
    dec bx
    call gen_random
    mov [secuencia + bx], al

    ; ==================================================================
    ; TURNO JUGADOR 1
    ; ==================================================================
    cmp byte ptr [vivo1], 0
    je  skip_p1

    call clear_screen
    mov dx, offset msg_j1hdr
    call print_string
    call show_status

    cmp byte ptr [vivo2], 0
    jne p1_j2alive
    mov dx, offset msg_j2elim
    call print_string
p1_j2alive:

    mov dx, offset msg_mira
    call print_string
    call show_sequence

    mov dx, offset msg_listo
    call print_string
    call wait_enter

    call clear_screen
    mov dx, offset msg_j1hdr
    call print_string
    call show_status
    mov dx, offset msg_repite
    call print_string

    call get_and_validate
    jc  p1_falla

    mov dx, offset msg_bien
    call print_string
    call beep_ok
    mov ax, [long_seq]
    mov [puntaje1], ax
    call delay_long
    jmp skip_p1

p1_falla:
    mov dx, offset msg_mal
    call print_string
    mov dx, offset msg_elim1
    call print_string
    call beep_err
    mov byte ptr [vivo1], 0
    call delay_long

skip_p1:

    ; ==================================================================
    ; TURNO JUGADOR 2
    ; ==================================================================
    cmp byte ptr [vivo2], 0
    je  skip_p2

    call clear_screen
    mov dx, offset msg_j2hdr
    call print_string
    call show_status

    cmp byte ptr [vivo1], 0
    jne p2_j1alive
    mov dx, offset msg_j1elim
    call print_string
p2_j1alive:

    mov dx, offset msg_mira
    call print_string
    call show_sequence

    mov dx, offset msg_listo
    call print_string
    call wait_enter

    call clear_screen
    mov dx, offset msg_j2hdr
    call print_string
    call show_status
    mov dx, offset msg_repite
    call print_string

    call get_and_validate
    jc  p2_falla

    mov dx, offset msg_bien
    call print_string
    call beep_ok
    mov ax, [long_seq]
    mov [puntaje2], ax
    call delay_long
    jmp skip_p2

p2_falla:
    mov dx, offset msg_mal
    call print_string
    mov dx, offset msg_elim2
    call print_string
    call beep_err
    mov byte ptr [vivo2], 0
    call delay_long

skip_p2:
    jmp game_loop

nivel_maximo:
    call clear_screen
    mov dx, offset msg_maxniv
    call print_string
    call delay_long

; ==================================================================
; PANTALLA FINAL
; ==================================================================
end_game:
    call clear_screen
    mov dx, offset msg_fin
    call print_string
    mov dx, offset msg_sep
    call print_string

    mov dx, offset msg_res1
    call print_string
    mov ax, [puntaje1]
    call print_num
    mov dx, offset msg_res_pt
    call print_string

    mov dx, offset msg_res2
    call print_string
    mov ax, [puntaje2]
    call print_num
    mov dx, offset msg_res_pt
    call print_string

    mov dx, offset msg_sep
    call print_string

    mov ax, [puntaje1]
    cmp ax, [puntaje2]
    jg  j1_gana
    jl  j2_gana

    mov dx, offset msg_empate
    call print_string
    jmp show_bye

j1_gana:
    mov dx, offset msg_gana1
    call print_string
    jmp show_bye

j2_gana:
    mov dx, offset msg_gana2
    call print_string

show_bye:
    mov dx, offset msg_sep
    call print_string
    mov dx, offset msg_bye
    call print_string

    mov ax, 4C00h
    int 21h

main endp

; =====================================================================
; PROCEDIMIENTOS
; =====================================================================

; ---------------------------------------------------------------------
; GEN_RANDOM
; LCG de Knuth: seed = seed * 25173 + 13849  (mod 65536)
; Salida: AL = 0..3  (bits 9:8 del seed)
; Preserva: BX, CX, DX
; ---------------------------------------------------------------------
gen_random proc

    push bx
    push cx
    push dx

    mov ax, [rand_seed]
    mov bx, 25173
    mul bx
    add ax, 13849
    mov [rand_seed], ax

    mov cl, 8
    shr ax, cl
    and ax, 0003h

    pop dx
    pop cx
    pop bx
    ret

gen_random endp

; ---------------------------------------------------------------------
; SHOW_SEQUENCE
; Muestra los simbolos de la secuencia con pausa entre cada uno.
; Preserva: AX, BX, CX, SI
; ---------------------------------------------------------------------
show_sequence proc

    push ax
    push bx
    push cx
    push si

    mov cx, [long_seq]
    xor si, si

    test cx, cx
    jz  ss_fin

ss_bucle:
    xor bx, bx
    mov bl, [secuencia + si]
    mov al, [mapa_sim + bx]

    mov ah, 0Eh
    xor bx, bx
    int 10h

    mov al, '-'
    mov ah, 0Eh
    xor bx, bx
    int 10h

    call delay_medium

    inc si
    dec cx
    jnz ss_bucle

ss_fin:
    pop si
    pop cx
    pop bx
    pop ax
    ret

show_sequence endp

; ---------------------------------------------------------------------
; GET_AND_VALIDATE
; Lee la entrada del jugador y la compara contra la secuencia.
; Retorna: CF=0 correcto, CF=1 error
; Preserva: BX, CX, SI
; ---------------------------------------------------------------------
get_and_validate proc

    push bx
    push cx
    push si

    mov cx, [long_seq]
    xor si, si

    test cx, cx
    jz  gv_ok

gv_leer:
    mov ah, 00h
    int 16h

    cmp al, '1'
    jb  gv_leer
    cmp al, '4'
    ja  gv_leer

    sub al, '1'
    xor ah, ah

    cmp al, [secuencia + si]
    jne gv_error

    mov bx, ax
    mov al, [mapa_sim + bx]
    mov ah, 0Eh
    xor bx, bx
    int 10h

    mov al, ' '
    mov ah, 0Eh
    xor bx, bx
    int 10h

    inc si
    dec cx
    jnz gv_leer

gv_ok:
    pop si
    pop cx
    pop bx
    clc
    ret

gv_error:
    pop si
    pop cx
    pop bx
    stc
    ret

get_and_validate endp

; ---------------------------------------------------------------------
; SHOW_STATUS
; Muestra ronda actual y puntajes.
; Preserva: AX, DX
; ---------------------------------------------------------------------
show_status proc

    push ax
    push dx

    mov dx, offset msg_nivel
    call print_string
    mov ax, [long_seq]
    call print_num
    mov dx, offset msg_crlf
    call print_string

    mov dx, offset msg_pj1
    call print_string
    mov ax, [puntaje1]
    call print_num
    mov dx, offset msg_pts_s
    call print_string

    mov dx, offset msg_pj2
    call print_string
    mov ax, [puntaje2]
    call print_num
    mov dx, offset msg_pts_s
    call print_string

    mov dx, offset msg_sep
    call print_string

    pop dx
    pop ax
    ret

show_status endp

; ---------------------------------------------------------------------
; PRINT_NUM
; Imprime AX como numero decimal con INT 10h.
; Rango: 0..65535
;
; CORRECCION BUG 7: xor cx, cx despues de los push iniciales.
; Sin esto, si CX != 0 al entrar, pn_imprimir intenta sacar mas
; elementos del stack de los apilados, corrompiendo registros y
; la direccion de retorno -> crash.
;
; Preserva: AX, BX, CX, DX
; ---------------------------------------------------------------------
print_num proc

    push ax
    push bx
    push cx
    push dx
    xor cx, cx           ; [BUG 7 CORREGIDO] inicializar contador a 0

    test ax, ax
    jnz pn_extraer

    mov ah, 0Eh
    mov al, '0'
    xor bx, bx
    int 10h
    jmp pn_done

pn_extraer:
    test ax, ax
    jz  pn_imprimir

    xor dx, dx
    mov bx, 10
    div bx
    push dx
    inc cx
    jmp pn_extraer

pn_imprimir:
    test cx, cx
    jz  pn_done

    pop dx
    mov al, dl
    add al, '0'
    mov ah, 0Eh
    push cx
    xor bx, bx
    int 10h
    pop cx
    dec cx
    jmp pn_imprimir

pn_done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

print_num endp

; ---------------------------------------------------------------------
; PRINT_STRING
; Imprime cadena terminada en '$' con INT 21h / AH=09h.
; DS:DX apunta a la cadena.
; Preserva: AX
; ---------------------------------------------------------------------
print_string proc

    push ax
    mov ah, 09h
    int 21h
    pop ax
    ret

print_string endp

; ---------------------------------------------------------------------
; CLEAR_SCREEN
; Limpia la pantalla y posiciona el cursor en (0,0).
; Preserva: AX, BX, CX, DX
; ---------------------------------------------------------------------
clear_screen proc

    push ax
    push bx
    push cx
    push dx

    mov ah, 06h
    xor al, al
    mov bh, 07h
    xor cx, cx
    mov dh, 24
    mov dl, 79
    int 10h

    mov ah, 02h
    xor bh, bh
    xor dx, dx
    int 10h

    pop dx
    pop cx
    pop bx
    pop ax
    ret

clear_screen endp

; ---------------------------------------------------------------------
; WAIT_ENTER
; Espera hasta que el jugador presione ENTER (ASCII 13).
; Preserva: AX
; ---------------------------------------------------------------------
wait_enter proc

    push ax

we_loop:
    mov ah, 00h
    int 16h
    cmp al, 13
    jne we_loop

    pop ax
    ret

wait_enter endp

; ---------------------------------------------------------------------
; DELAY_MEDIUM  (~0.82 segundos = 15 ticks a 18.2 ticks/seg)
; Usa diferencia de ticks para manejar correctamente el desbordamiento
; del timer de 16 bits.
; Preserva: AX, BX, CX, DX
; ---------------------------------------------------------------------
delay_medium proc

    push ax
    push bx
    push cx
    push dx

    xor ax, ax
    int 1Ah
    mov bx, dx

dm_esperar:
    xor ax, ax
    int 1Ah
    mov ax, dx
    sub ax, bx
    cmp ax, 15
    jb  dm_esperar

    pop dx
    pop cx
    pop bx
    pop ax
    ret

delay_medium endp

; ---------------------------------------------------------------------
; DELAY_LONG  (~1.6 segundos = 29 ticks a 18.2 ticks/seg)
; Misma tecnica que delay_medium.
; Preserva: AX, BX, CX, DX
; ---------------------------------------------------------------------
delay_long proc

    push ax
    push bx
    push cx
    push dx

    xor ax, ax
    int 1Ah
    mov bx, dx

dl_esperar:
    xor ax, ax
    int 1Ah
    mov ax, dx
    sub ax, bx
    cmp ax, 29
    jb  dl_esperar

    pop dx
    pop cx
    pop bx
    pop ax
    ret

delay_long endp

; ---------------------------------------------------------------------
; BEEP_OK - Doble pitido de exito
; Preserva: AX, DX
; ---------------------------------------------------------------------
beep_ok proc

    push ax
    push dx

    mov ah, 02h
    mov dl, 07h
    int 21h
    mov ah, 02h
    mov dl, 07h
    int 21h

    pop dx
    pop ax
    ret

beep_ok endp

; ---------------------------------------------------------------------
; BEEP_ERR - Un pitido de error
; Preserva: AX, DX
; ---------------------------------------------------------------------
beep_err proc

    push ax
    push dx

    mov ah, 02h
    mov dl, 07h
    int 21h

    pop dx
    pop ax
    ret

beep_err endp

end main