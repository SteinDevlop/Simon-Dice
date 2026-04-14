; =====================================================================
;  SIMÓN DICE (Simon Says) - Juego de Memoria para 2 Jugadores
;  Lenguaje: Ensamblador Intel 8086
;  Entorno:  EMU8086 (archivo EXE, modelo SMALL)
; =====================================================================
;
;  DESCRIPCIÓN GENERAL:
;    El juego genera una secuencia creciente de símbolos (A, B, C, D).
;    En cada ronda ambos jugadores observan la secuencia y deben
;    repetirla usando las teclas [1][2][3][4]. Si un jugador falla,
;    queda eliminado. El juego termina cuando los dos son eliminados
;    y gana quien haya alcanzado el nivel más alto.
;
;  INTERRUPCIONES UTILIZADAS:
;    INT 10h  →  Salida en pantalla (teletype, scroll, cursor)
;    INT 16h  →  Entrada por teclado (sin eco)
;    INT 1Ah  →  Timer del sistema (semilla aleatoria y retardos)
;    INT 21h  →  Servicios DOS (imprimir cadena, terminar programa)
;
;  COMPILAR Y EJECUTAR EN EMU8086:
;    1. Abrir EMU8086
;    2. File → New → EXE Template
;    3. Borrar el template y pegar este código completo
;    4. Menú: Assembler → Assemble (F5)
;    5. Menú: Run → Run (F9) o paso a paso con F8
;
;  TECLAS DEL JUEGO:
;    [1] = Símbolo A    [2] = Símbolo B
;    [3] = Símbolo C    [4] = Símbolo D
;    [ENTER] = Confirmar que estás listo para ingresar la secuencia
; =====================================================================

.model small
.stack 200h          ; 512 bytes de pila (suficiente para este programa)

; =====================================================================
; SEGMENTO DE DATOS
; =====================================================================
.data

; ─────────────────────────────────────────────────────────────────────
; MENSAJES DE INTERFAZ (terminados en '$' para INT 21h / AH=09h)
; ─────────────────────────────────────────────────────────────────────

msg_titulo  db '=========================================',13,10
            db '    S I M O N   D I C E  -  v1.0       ',13,10
            db '    Juego de Memoria  |  2 Jugadores    ',13,10
            db '=========================================',13,10,'$'

msg_reglas  db 13,10
            db '  TECLAS VALIDAS EN EL JUEGO:',13,10
            db '    [1] = Simbolo  A',13,10
            db '    [2] = Simbolo  B',13,10
            db '    [3] = Simbolo  C',13,10
            db '    [4] = Simbolo  D',13,10
            db 13,10
            db '  OBJETIVO:',13,10
            db '    Observa la secuencia y repitela exactamente.',13,10
            db '    La secuencia crece un simbolo cada ronda.',13,10
            db '    Si fallas, quedas eliminado.',13,10
            db '    Gana quien llegue mas lejos!',13,10,'$'

msg_enter   db 13,10,'  >> Presiona ENTER para comenzar... <<$'

msg_sep     db '  -----------------------------------------',13,10,'$'

msg_j1hdr   db 13,10
            db '  +---------------------------------------+',13,10
            db '  |       *** TURNO: JUGADOR 1 ***        |',13,10
            db '  +---------------------------------------+',13,10,'$'

msg_j2hdr   db 13,10
            db '  +---------------------------------------+',13,10
            db '  |       *** TURNO: JUGADOR 2 ***        |',13,10
            db '  +---------------------------------------+',13,10,'$'

msg_nivel   db '  Nivel actual : ','$'
msg_pj1     db '   Puntaje J1  : ','$'
msg_pj2     db '   Puntaje J2  : ','$'
msg_pts_s   db ' pts',13,10,'$'

msg_mira    db 13,10,'  [ Observa la secuencia ]',13,10
            db '  > ','$'

msg_listo   db 13,10,13,10
            db '  Presiona ENTER cuando estes listo para repetir...$'

msg_repite  db 13,10,'  [ Repite la secuencia ] : ','$'

msg_bien    db 13,10
            db '  ** CORRECTO! Muy bien! **',13,10,'$'

msg_mal     db 13,10
            db '  ** ERROR! Secuencia incorrecta! **',13,10,'$'

msg_elim1   db '  >>> JUGADOR 1 ELIMINADO <<<',13,10,'$'
msg_elim2   db '  >>> JUGADOR 2 ELIMINADO <<<',13,10,'$'

msg_j1elim  db '  (Jugador 1 ya no puede jugar)',13,10,'$'
msg_j2elim  db '  (Jugador 2 ya no puede jugar)',13,10,'$'

msg_fin     db 13,10
            db '  =========================================',13,10
            db '           F I N   D E L   J U E G O      ',13,10
            db '  =========================================',13,10,'$'

msg_res1    db '  Puntaje Final  Jugador 1 : ','$'
msg_res2    db '  Puntaje Final  Jugador 2 : ','$'
msg_res_pt  db ' puntos',13,10,'$'

msg_gana1   db 13,10
            db '  *** GANADOR: JUGADOR 1 !!! ***',13,10,'$'

msg_gana2   db 13,10
            db '  *** GANADOR: JUGADOR 2 !!! ***',13,10,'$'

msg_empate  db 13,10
            db '  *** RESULTADO: EMPATE ***',13,10,'$'

msg_bye     db 13,10
            db '  Gracias por jugar Simon Dice!',13,10
            db '  Hasta la proxima...',13,10,13,10,'$'

msg_crlf    db 13,10,'$'

; ─────────────────────────────────────────────────────────────────────
; VARIABLES DEL JUEGO
; ─────────────────────────────────────────────────────────────────────

secuencia   db 50 dup(0)    ; Array con la secuencia (valores 0-3)
                             ; 0=A, 1=B, 2=C, 3=D
                             ; Máximo 50 rondas

long_seq    dw 0             ; Longitud actual de la secuencia

rand_seed   dw 0ABCDh       ; Semilla inicial del generador LCG
                             ; Se actualiza con el timer al inicio

puntaje1    dw 0             ; Puntaje J1 = nivel más alto superado
puntaje2    dw 0             ; Puntaje J2

vivo1       db 1             ; Estado J1: 1=activo, 0=eliminado
vivo2       db 1             ; Estado J2

; Mapa de índices [0..3] a caracteres de símbolo
mapa_sim    db 'A','B','C','D'

; =====================================================================
; SEGMENTO DE CÓDIGO
; =====================================================================
.code

; ─────────────────────────────────────────────────────────────────────
; MAIN - Punto de entrada del programa
;
; Flujo principal:
;   1. Configurar DS, limpiar pantalla, mostrar título/reglas
;   2. Inicializar semilla aleatoria con el timer del sistema
;   3. Inicializar variables del juego
;   4. Ejecutar el bucle principal (game_loop)
;   5. Mostrar resultados finales y terminar
; ─────────────────────────────────────────────────────────────────────
main proc

    ; ── Configurar segmento de datos ──────────────────────────────────
    ; En .model small, DS no apunta automáticamente a .data
    mov ax, @data           ; AX = dirección del segmento de datos
    mov ds, ax              ; DS → segmento .data

    ; ── Pantalla de bienvenida ─────────────────────────────────────────
    call clear_screen

    mov dx, offset msg_titulo
    call print_string

    mov dx, offset msg_reglas
    call print_string

    mov dx, offset msg_enter
    call print_string
    call wait_enter          ; esperar que el jugador presione ENTER

    ; ── Semilla aleatoria con el timer del sistema ─────────────────────
    ; INT 1Ah con AH=0 devuelve CX:DX = ticks del sistema (54ms c/u)
    xor ax, ax               ; AH=0 → función "leer hora del sistema"
    int 1Ah                  ; CX = ticks altos, DX = ticks bajos

    ; DX cambia 18.2 veces/segundo → excelente para semilla aleatoria
    or  dx, dx               ; ¿DX es cero? (raro pero posible al inicio)
    jnz seed_ok
    mov dx, 0F3A7h           ; valor de respaldo por si acaso
seed_ok:
    mov [rand_seed], dx      ; guardar semilla inicial

    ; ── Inicializar estado del juego ───────────────────────────────────
    mov word ptr [long_seq],  0    ; secuencia vacía al inicio
    mov word ptr [puntaje1],  0    ; puntajes en cero
    mov word ptr [puntaje2],  0
    mov byte ptr [vivo1], 1        ; ambos jugadores activos
    mov byte ptr [vivo2], 1

    ; ================================================================
    ; BUCLE PRINCIPAL DEL JUEGO
    ;
    ; Cada iteración = una ronda completa:
    ;   → Se agrega un símbolo a la secuencia
    ;   → Jugador 1 observa y trata de repetir (si está activo)
    ;   → Jugador 2 observa y trata de repetir (si está activo)
    ; ================================================================
game_loop:

    ; ── ¿Ambos jugadores eliminados? → Fin del juego ─────────────────
    mov al, [vivo1]
    or  al, [vivo2]          ; OR: si ambos son 0, resultado = 0
    jz  end_game             ; ZF=1 → los dos están eliminados

    ; ── Generar siguiente elemento de la secuencia ────────────────────
    inc word ptr [long_seq]  ; crecer la secuencia en 1

    mov bx, [long_seq]
    dec bx                   ; BX = índice del nuevo elemento (0-based)
    push bx                  ; preservar BX porque gen_random lo modifica

    call gen_random          ; → AL = número aleatorio 0..3

    pop bx                   ; restaurar índice
    mov [secuencia + bx], al ; guardar nuevo símbolo en la secuencia

    ; ================================================================
    ; TURNO DEL JUGADOR 1
    ; ================================================================
    cmp byte ptr [vivo1], 0
    je  skip_p1              ; J1 eliminado → saltar su turno

    ; Mostrar encabezado y estado
    call clear_screen
    mov dx, offset msg_j1hdr
    call print_string
    call show_status         ; muestra nivel y puntajes actuales

    ; Aviso si J2 ya está eliminado
    cmp byte ptr [vivo2], 0
    jne p1_j2alive
    mov dx, offset msg_j2elim
    call print_string
p1_j2alive:

    ; Mostrar la secuencia con retardos visuales
    mov dx, offset msg_mira
    call print_string
    call show_sequence       ; imprime A-B-C-... con pausa entre cada uno

    ; Pedir que presione ENTER para ingresar su respuesta
    mov dx, offset msg_listo
    call print_string
    call wait_enter

    ; Limpiar pantalla y pedir la repetición de la secuencia
    call clear_screen
    mov dx, offset msg_j1hdr
    call print_string
    call show_status
    mov dx, offset msg_repite
    call print_string

    ; Capturar y validar la entrada del jugador 1
    ; Resultado: CF=0 → correcto, CF=1 → error
    call get_and_validate
    jc  p1_falla

    ; ── J1 respondió correctamente ────────────────────────────────────
    mov dx, offset msg_bien
    call print_string
    call beep_ok             ; sonido de éxito
    mov ax, [long_seq]       ; actualizar puntaje = nivel alcanzado
    mov [puntaje1], ax
    call delay_long          ; pausa para leer el mensaje
    jmp skip_p1

    ; ── J1 falló ──────────────────────────────────────────────────────
p1_falla:
    mov dx, offset msg_mal
    call print_string
    mov dx, offset msg_elim1
    call print_string
    call beep_err            ; sonido de error
    mov byte ptr [vivo1], 0  ; eliminar jugador 1
    call delay_long

skip_p1:

    ; ================================================================
    ; TURNO DEL JUGADOR 2
    ; ================================================================
    cmp byte ptr [vivo2], 0
    je  skip_p2              ; J2 eliminado → saltar su turno

    call clear_screen
    mov dx, offset msg_j2hdr
    call print_string
    call show_status

    ; Aviso si J1 ya está eliminado
    cmp byte ptr [vivo1], 0
    jne p2_j1alive
    mov dx, offset msg_j1elim
    call print_string
p2_j1alive:

    ; Mostrar la misma secuencia a J2
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

    ; ── J2 respondió correctamente ────────────────────────────────────
    mov dx, offset msg_bien
    call print_string
    call beep_ok
    mov ax, [long_seq]
    mov [puntaje2], ax
    call delay_long
    jmp skip_p2

    ; ── J2 falló ──────────────────────────────────────────────────────
p2_falla:
    mov dx, offset msg_mal
    call print_string
    mov dx, offset msg_elim2
    call print_string
    call beep_err
    mov byte ptr [vivo2], 0
    call delay_long

skip_p2:
    jmp game_loop            ; siguiente ronda

    ; ================================================================
    ; FIN DEL JUEGO - Ambos jugadores han sido eliminados
    ; ================================================================
end_game:
    call clear_screen

    mov dx, offset msg_fin
    call print_string

    mov dx, offset msg_sep
    call print_string

    ; ── Mostrar puntajes finales ───────────────────────────────────────
    mov dx, offset msg_res1
    call print_string
    mov ax, [puntaje1]
    call print_num           ; imprime número en decimal
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

    ; ── Determinar y anunciar al ganador ──────────────────────────────
    mov ax, [puntaje1]
    cmp ax, [puntaje2]
    jg  j1_gana              ; J1 > J2 → J1 gana
    jl  j2_gana              ; J1 < J2 → J2 gana

    ; Empate (misma puntuación)
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

    ; ── Terminar programa: INT 21h / AH=4Ch, AL=código de salida ──────
    mov ax, 4C00h            ; AH=4Ch (terminar), AL=0 (sin error)
    int 21h

main endp

; =====================================================================
; PROCEDIMIENTOS DEL JUEGO
; =====================================================================

; ─────────────────────────────────────────────────────────────────────
; GEN_RANDOM
; Genera un número pseudoaleatorio en el rango [0..3] usando el
; algoritmo LCG (Linear Congruential Generator):
;
;   seed_nuevo = (seed_actual × 25173 + 13849) mod 65536
;
; Las constantes son de Donald Knuth y tienen período completo para
; m=2^16. Se usan los bits 9:8 del seed en lugar de los bajos porque
; los bits de orden inferior de un LCG tienen menor aleatoriedad.
;
; Salida  : AL = 0, 1, 2 ó 3
; Modifica: AX, BX, CX, DX
; ─────────────────────────────────────────────────────────────────────
gen_random proc

    mov ax, [rand_seed]      ; AX = seed actual
    mov bx, 25173            ; multiplicador LCG
    mul bx                   ; DX:AX = AX × 25173 (solo AX importa)
    add ax, 13849            ; incremento LCG
    mov [rand_seed], ax      ; guardar nuevo seed (mod 65536 automático)

    ; Extraer bits 9:8 para mayor aleatoriedad
    mov cl, 8
    shr ax, cl               ; AX >>= 8 (descartar 8 bits bajos)
    and ax, 0003h            ; AL = bits 1:0 = valor 0..3

    ret
gen_random endp

; ─────────────────────────────────────────────────────────────────────
; SHOW_SEQUENCE
; Muestra la secuencia completa (hasta long_seq símbolos) en pantalla,
; con un retardo visual entre cada símbolo para que sea memorizable.
;
; Cada símbolo se muestra como: X- (donde X = A, B, C ó D)
;
; Usa     : long_seq, secuencia[], mapa_sim[]
; Modifica: AX, BX, CX, SI
; ─────────────────────────────────────────────────────────────────────
show_sequence proc

    push ax
    push bx
    push cx
    push si

    mov cx, [long_seq]       ; CX = número de símbolos a mostrar
    xor si, si               ; SI = índice = 0

show_next:
    ; Obtener valor del símbolo en posición SI (valor 0-3)
    mov al, [secuencia + si] ; AL = 0,1,2 ó 3
    xor ah, ah               ; limpiar AH (simula MOVZX de 16 bits)
    mov bx, ax               ; BX = índice para mapa_sim

    ; Traducir índice a carácter (A, B, C ó D)
    mov al, [mapa_sim + bx]  ; AL = 'A','B','C' ó 'D'

    ; Imprimir símbolo usando INT 10h / AH=0Eh (teletype output)
    mov ah, 0Eh
    xor bx, bx               ; BH=0 (página de video), BL=color
    int 10h

    ; Imprimir guión separador
    mov al, '-'
    mov ah, 0Eh
    xor bx, bx
    int 10h

    ; Pausa entre símbolos (~0.8 segundos) para que se pueda memorizar
    call delay_medium

    inc si
    loop show_next           ; LOOP decrementa CX, salta si CX≠0

    pop si
    pop cx
    pop bx
    pop ax
    ret

show_sequence endp

; ─────────────────────────────────────────────────────────────────────
; GET_AND_VALIDATE
; Lee teclas del jugador una a una y las compara contra la secuencia
; almacenada. Solo acepta teclas '1'-'4'; ignora cualquier otra.
;
; Muestra cada símbolo correcto a medida que el jugador lo ingresa.
; En el primer error, retorna inmediatamente con CF=1.
;
; Salida  : CF=0 → toda la secuencia fue correcta
;           CF=1 → el jugador cometió un error
; Modifica: AX, BX, CX, SI
; ─────────────────────────────────────────────────────────────────────
get_and_validate proc

    push bx
    push cx
    push si

    mov cx, [long_seq]       ; CX = número de teclas a leer
    xor si, si               ; SI = índice = 0

gv_next_key:
    ; Leer tecla del teclado (INT 16h / AH=0 → espera tecla)
    mov ah, 00h
    int 16h                  ; AL = código ASCII de la tecla presionada

    ; ── Filtrar teclas válidas (solo '1','2','3','4') ─────────────────
    cmp al, '1'
    jb  gv_next_key          ; tecla < '1': ignorar, pedir otra
    cmp al, '4'
    ja  gv_next_key          ; tecla > '4': ignorar

    ; ── Convertir ASCII '1'...'4' a índice 0..3 ──────────────────────
    sub al, '1'              ; '1'→0, '2'→1, '3'→2, '4'→3
    xor ah, ah               ; limpiar AH (AX = índice 0-3)

    ; ── Comparar con el símbolo esperado en la secuencia ─────────────
    cmp al, [secuencia + si] ; ¿coincide con la posición SI?
    jne gv_error             ; no coincide → error

    ; ── Tecla correcta: mostrar el símbolo correspondiente ───────────
    mov bx, ax               ; BX = índice (0-3)
    mov al, [mapa_sim + bx]  ; AL = carácter del símbolo
    mov ah, 0Eh
    xor bx, bx
    int 10h                  ; imprimir carácter

    mov al, ' '              ; espacio separador
    mov ah, 0Eh
    int 10h

    inc si                   ; avanzar al siguiente símbolo
    loop gv_next_key         ; pedir siguiente tecla

    ; ── Toda la secuencia completada correctamente ────────────────────
    pop si
    pop cx
    pop bx
    clc                      ; CF=0 → éxito
    ret

gv_error:
    ; ── Error: tecla incorrecta ───────────────────────────────────────
    pop si
    pop cx
    pop bx
    stc                      ; CF=1 → error
    ret

get_and_validate endp

; ─────────────────────────────────────────────────────────────────────
; SHOW_STATUS
; Muestra una línea con el nivel actual y los puntajes de ambos
; jugadores. Se llama antes de cada turno para contextualizar.
;
; Modifica: AX, DX
; ─────────────────────────────────────────────────────────────────────
show_status proc

    push ax
    push dx

    ; "  Nivel actual : N"
    mov dx, offset msg_nivel
    call print_string
    mov ax, [long_seq]
    call print_num

    mov dx, offset msg_crlf
    call print_string

    ; "   Puntaje J1  : N pts"
    mov dx, offset msg_pj1
    call print_string
    mov ax, [puntaje1]
    call print_num
    mov dx, offset msg_pts_s
    call print_string

    ; "   Puntaje J2  : N pts"
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

; ─────────────────────────────────────────────────────────────────────
; PRINT_NUM
; Convierte el valor de AX a cadena decimal y lo imprime en pantalla
; usando INT 10h (teletype). Maneja correctamente AX=0.
;
; Algoritmo: extrae dígitos dividiendo por 10 (de menor a mayor),
; los guarda en el stack, luego los saca y los imprime (mayor a menor).
;
; Entrada : AX = número a imprimir (0..65535)
; Modifica: AX, BX, CX, DX
; ─────────────────────────────────────────────────────────────────────
print_num proc

    push ax
    push bx
    push cx
    push dx

    ; BX = divisor (base 10)
    mov bx, 10
    xor cx, cx               ; CX = contador de dígitos en el stack

    ; ── Caso especial: AX = 0 ─────────────────────────────────────────
    test ax, ax
    jnz pn_extract

    ; Solo imprimir el carácter '0'
    mov ah, 0Eh
    mov al, '0'
    xor bx, bx
    int 10h
    jmp pn_done

    ; ── Extracción de dígitos (del menos significativo al más) ────────
pn_extract:
    test ax, ax
    jz  pn_output            ; AX=0: todos los dígitos ya extraídos

    xor dx, dx               ; limpiar DX para la división 32÷16
    mov bx, 10               ; asegurar BX=10 en cada iteración
    div bx                   ; AX = cociente, DX = resto (0..9)
    push dx                  ; apilar dígito (orden invertido)
    inc cx                   ; un dígito más
    jmp pn_extract

    ; ── Impresión de dígitos (en orden correcto) ──────────────────────
pn_output:
    test cx, cx
    jz  pn_done              ; CX=0: todos impresos

    pop dx                   ; recuperar siguiente dígito (DL = 0..9)
    mov ah, 0Eh
    mov al, dl
    add al, '0'              ; convertir a código ASCII
    push cx                  ; preservar contador en el stack
    xor bx, bx               ; BH=0 (página), BL=0 (color)
    int 10h                  ; imprimir dígito
    pop cx                   ; restaurar contador
    dec cx
    jmp pn_output

pn_done:
    ; Restaurar registros salvados al inicio del procedimiento
    pop dx
    pop cx
    pop bx
    pop ax
    ret

print_num endp

; ─────────────────────────────────────────────────────────────────────
; PRINT_STRING
; Imprime una cadena terminada en '$' usando el servicio DOS.
; Más eficiente que INT 10h para cadenas largas con CR/LF.
;
; Entrada : DX = offset de la cadena en DS
; Modifica: AX
; ─────────────────────────────────────────────────────────────────────
print_string proc

    mov ah, 09h              ; INT 21h / AH=9: imprimir cadena en DS:DX
    int 21h
    ret

print_string endp

; ─────────────────────────────────────────────────────────────────────
; CLEAR_SCREEN
; Limpia la pantalla entera usando INT 10h / AH=06h (scroll up).
; Cuando AL=0, el scroll limpia toda el área especificada.
; Luego reposiciona el cursor en la esquina superior izquierda (0,0).
;
; Modifica: AX, BX, CX, DX
; ─────────────────────────────────────────────────────────────────────
clear_screen proc

    push ax
    push bx
    push cx
    push dx

    ; INT 10h / AH=06h: Scroll Up
    ;   AL = 0          → limpiar toda el área (sin scroll)
    ;   BH = 07h        → atributo: texto blanco sobre fondo negro
    ;   CH:CL = 00:00   → esquina superior izquierda (fila=0, col=0)
    ;   DH:DL = 24:79   → esquina inferior derecha (fila=24, col=79)
    mov ah, 06h
    mov al, 00h
    mov bh, 07h
    xor cx, cx               ; CH=0, CL=0
    mov dh, 24               ; última fila (pantalla de 25 líneas)
    mov dl, 79               ; última columna (pantalla de 80 cols)
    int 10h

    ; INT 10h / AH=02h: Mover cursor a posición (fila=0, col=0)
    mov ah, 02h
    xor bh, bh               ; página de video 0
    xor dx, dx               ; DH=0 (fila), DL=0 (columna)
    int 10h

    pop dx
    pop cx
    pop bx
    pop ax
    ret

clear_screen endp

; ─────────────────────────────────────────────────────────────────────
; WAIT_ENTER
; Bloquea la ejecución hasta que el usuario presione ENTER (código 13).
; Ignora cualquier otra tecla.
;
; Modifica: AX
; ─────────────────────────────────────────────────────────────────────
wait_enter proc

    push ax

we_loop:
    mov ah, 00h
    int 16h                  ; leer tecla: AL = ASCII, AH = scan code
    cmp al, 13               ; ¿es ENTER (CR = 0Dh = 13)?
    jne we_loop              ; no → ignorar y esperar

    pop ax
    ret

wait_enter endp

; ─────────────────────────────────────────────────────────────────────
; DELAY_MEDIUM
; Retardo de aproximadamente 0.82 segundos.
; Usa el timer del sistema: 18.2 ticks/segundo × 15 ≈ 0.82 s
;
; El timer se lee con INT 1Ah (AH=0) que devuelve CX:DX = ticks
; desde la medianoche. Solo usamos DX (16 bits bajos), suficiente
; para retardos cortos (DX desborda cada ~3600 segundos).
;
; Modifica: AX, BX, DX
; ─────────────────────────────────────────────────────────────────────
delay_medium proc

    push ax
    push bx
    push dx

    xor ax, ax
    int 1Ah                  ; leer timer: DX = ticks bajos
    mov bx, dx               ; BX = tick inicial
    add bx, 15               ; BX = tick objetivo (~0.82 seg)

dm_wait:
    xor ax, ax
    int 1Ah                  ; DX = tick actual
    cmp dx, bx
    jb  dm_wait              ; si tick_actual < tick_objetivo → esperar

    pop dx
    pop bx
    pop ax
    ret

delay_medium endp

; ─────────────────────────────────────────────────────────────────────
; DELAY_LONG
; Retardo de aproximadamente 1.6 segundos.
; 18.2 ticks/segundo × 29 ≈ 1.59 segundos
; Se usa para que el jugador pueda leer mensajes de éxito/error.
;
; Modifica: AX, BX, DX
; ─────────────────────────────────────────────────────────────────────
delay_long proc

    push ax
    push bx
    push dx

    xor ax, ax
    int 1Ah
    mov bx, dx
    add bx, 29               ; ~1.59 segundos

dl_wait:
    xor ax, ax
    int 1Ah
    cmp dx, bx
    jb  dl_wait

    pop dx
    pop bx
    pop ax
    ret

delay_long endp

; ─────────────────────────────────────────────────────────────────────
; BEEP_OK
; Emite un beep de éxito usando el carácter BEL (07h).
; En DOS/EMU8086 esto activa el altavoz del sistema.
;
; Modifica: AX, DX
; ─────────────────────────────────────────────────────────────────────
beep_ok proc

    push ax
    push dx

    ; INT 21h / AH=02h: imprimir carácter en DL
    mov ah, 02h
    mov dl, 07h              ; BEL (07h) = pitido del sistema
    int 21h

    ; Segundo beep para indicar éxito (doble tono)
    mov ah, 02h
    mov dl, 07h
    int 21h

    pop dx
    pop ax
    ret

beep_ok endp

; ─────────────────────────────────────────────────────────────────────
; BEEP_ERR
; Emite un único beep para indicar error.
;
; Modifica: AX, DX
; ─────────────────────────────────────────────────────────────────────
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

; ─────────────────────────────────────────────────────────────────────
; Directiva END: indica al ensamblador el punto de entrada del programa
; ─────────────────────────────────────────────────────────────────────
end main
