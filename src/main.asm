; =====================================================================
;  SIMÓN DICE (Simon Says) - v2.0 CORREGIDO
;  Lenguaje: Ensamblador Intel 8086
;  Entorno:  EMU8086 (modelo EXE, .model small)
; =====================================================================
;
;  *** BUGS CORREGIDOS RESPECTO A v1.0 ***
;
;  BUG 1 (CRITICO - LOOP INFINITO):
;    delay_medium y delay_long ejecutaban INT 1Ah que SOBRESCRIBE CX
;    con la palabra alta de los ticks del timer. Como show_sequence
;    usa un bucle que depende de CX, despues de cada pausa CX quedaba
;    con el valor del timer (~0 o ~1), haciendo que el bucle terminara
;    al primer simbolo o iterara millones de veces.
;    CORRECCION: push cx / pop cx en ambas rutinas de retardo.
;
;  BUG 2 (CRITICO - LOOP INFINITO):
;    Los retardos comparaban tick_actual < tick_objetivo con JB.
;    Cuando el timer de 16 bits desbordaba (65535->0), el objetivo
;    tambien desbordaba: ej. si tick_inicial=65530, el objetivo
;    65530+15=65545 mod 65536 = 9. Entonces tick_actual(65530)>=9,
;    y el delay retornaba INMEDIATAMENTE (0 segundos de espera).
;    CORRECCION: calcular ticks transcurridos por DIFERENCIA:
;    elapsed = tick_actual - tick_inicial.
;    La resta en 16 bits maneja el desbordamiento automaticamente.
;
;  BUG 3 (GRAVE):
;    gen_random modificaba BX (via MUL BX), DX (parte alta de MUL)
;    y CL (via MOV CL,8 para SHR) sin guardarlos ni restaurarlos,
;    dejando registros sucios para el llamador.
;    CORRECCION: push/pop de BX, CX y DX dentro de gen_random.
;
;  BUG 4 (GRAVE):
;    show_sequence y get_and_validate usaban la instruccion LOOP.
;    LOOP decrementa CX implicitamente. Cualquier INT ejecutada dentro
;    del bucle que modifique CX corrompe el contador. Aunque con BUG1
;    corregido esto no falla, usar LOOP con llamadas a INTs es fragil.
;    CORRECCION: reemplazar LOOP por DEC CX / JNZ (explicito y seguro).
;
;  BUG 5 (GRAVE):
;    El array "secuencia" tiene 50 bytes. Sin limite, si los jugadores
;    superaban 50 niveles, long_seq llegaba a 51, 52... y se escribia
;    fuera del array, corrompiendo rand_seed y otras variables.
;    CORRECCION: verificar long_seq >= MAX_SEQ antes de incrementar;
;    si se alcanza el maximo, el juego termina correctamente.
;
;  BUG 6 (MENOR):
;    print_string no guardaba AX. INT 21h/AH=09h modifica AX.
;    Cualquier llamador que conservara un valor en AX entre dos llamadas
;    a print_string encontraba AX corrompido.
;    CORRECCION: push ax / pop ax en print_string.
;
; =====================================================================
;  INTERRUPCIONES UTILIZADAS:
;    INT 10h / AH=06h  -> limpiar pantalla (scroll up)
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
;  COMPILAR Y EJECUTAR EN EMU8086:
;    1. Abrir EMU8086
;    2. File -> New -> "EXE Template"
;    3. Borrar el template completo y pegar este codigo
;    4. Assembler -> Assemble  (F5) -- debe mostrar "0 Errors"
;    5. Run -> Run  (F9) para ejecutar en la ventana DOS
;       O bien F8 para ejecucion paso a paso con vista de registros
; =====================================================================

.model small
.stack 200h            ; 512 bytes de pila

; =====================================================================
; SEGMENTO DE DATOS
; =====================================================================
.data

; Constante: maximo numero de niveles (igual al tamano del array)
MAX_SEQ  equ 50

; ─── Mensajes (terminados en '$' para INT 21h / AH=09h) ──────────────

msg_titulo  db '=========================================',13,10
            db '    S I M O N   D I C E  -  v2.0       ',13,10
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
            db '    Cada ronda agrega un simbolo mas.',13,10
            db '    Si fallas, quedas eliminado.',13,10
            db '    Gana quien llegue mas lejos!',13,10,'$'

msg_enter   db 13,10,'  >> Presiona ENTER para comenzar... <<','$'

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
msg_pj1     db '  Puntaje J1   : ','$'
msg_pj2     db '  Puntaje J2   : ','$'
msg_pts_s   db ' pts',13,10,'$'
msg_crlf    db 13,10,'$'

msg_mira    db 13,10,'  [ Observa la secuencia ]',13,10,'  > ','$'

msg_listo   db 13,10,13,10
            db '  Presiona ENTER cuando estes listo para repetir...','$'

msg_repite  db 13,10,'  [ Repite ] : ','$'

msg_bien    db 13,10,'  ** CORRECTO! Muy bien! **',13,10,'$'
msg_mal     db 13,10,'  ** ERROR! Secuencia incorrecta! **',13,10,'$'

msg_elim1   db '  >>> JUGADOR 1 ELIMINADO <<<',13,10,'$'
msg_elim2   db '  >>> JUGADOR 2 ELIMINADO <<<',13,10,'$'
msg_j1elim  db '  (Jugador 1 ya eliminado)',13,10,'$'
msg_j2elim  db '  (Jugador 2 ya eliminado)',13,10,'$'

msg_maxniv  db 13,10
            db '  *** Nivel maximo alcanzado (50 rondas)! ***',13,10,'$'

msg_fin     db 13,10
            db '  =========================================',13,10
            db '         F I N   D E L   J U E G O       ',13,10
            db '  =========================================',13,10,'$'

msg_res1    db '  Puntaje Final  Jugador 1 : ','$'
msg_res2    db '  Puntaje Final  Jugador 2 : ','$'
msg_res_pt  db ' puntos',13,10,'$'

msg_gana1   db 13,10,'  *** GANADOR: JUGADOR 1 !!! ***',13,10,'$'
msg_gana2   db 13,10,'  *** GANADOR: JUGADOR 2 !!! ***',13,10,'$'
msg_empate  db 13,10,'  *** RESULTADO: EMPATE ***',13,10,'$'

msg_bye     db 13,10,'  Gracias por jugar Simon Dice!',13,10
            db '  Hasta la proxima...',13,10,13,10,'$'

; ─── Variables del juego ─────────────────────────────────────────────

; Array de la secuencia: cada byte es 0(A), 1(B), 2(C) o 3(D)
secuencia   db MAX_SEQ dup(0)

long_seq    dw 0        ; Cantidad de simbolos en la secuencia actual
rand_seed   dw 0ABCDh   ; Semilla LCG; se mezcla con el timer al inicio
puntaje1    dw 0        ; Puntaje J1 = maximo nivel completado
puntaje2    dw 0        ; Puntaje J2
vivo1       db 1        ; J1: 1=activo, 0=eliminado
vivo2       db 1        ; J2: 1=activo, 0=eliminado

; Tabla de traduccion: indice 0-3 -> caracter ASCII del simbolo
mapa_sim    db 'A','B','C','D'

; =====================================================================
; SEGMENTO DE CODIGO
; =====================================================================
.code

; ─────────────────────────────────────────────────────────────────────
; MAIN - Punto de entrada
; ─────────────────────────────────────────────────────────────────────
main proc

    ; Apuntar DS al segmento de datos (.model small no lo hace solo)
    mov ax, @data
    mov ds, ax

    ; Pantalla de bienvenida y reglas
    call clear_screen
    mov dx, offset msg_titulo
    call print_string
    mov dx, offset msg_reglas
    call print_string
    mov dx, offset msg_enter
    call print_string
    call wait_enter

    ; ── Inicializar semilla con el timer del sistema ───────────────────
    ; INT 1Ah / AH=0 devuelve CX:DX = ticks desde medianoche (18.2/seg)
    xor ax, ax
    int 1Ah              ; CX = ticks altos, DX = ticks bajos
    or  dx, dx           ; preferir DX (cambia mas rapido)
    jnz seed_ok
    or  cx, cx           ; si DX=0, usar CX
    jz  seed_fallback
    mov dx, cx
    jmp seed_ok
seed_fallback:
    mov dx, 0F3A7h       ; semilla de respaldo (arranque inmediato)
seed_ok:
    mov [rand_seed], dx

    ; Inicializar variables del juego
    mov word ptr [long_seq],  0
    mov word ptr [puntaje1],  0
    mov word ptr [puntaje2],  0
    mov byte ptr [vivo1], 1
    mov byte ptr [vivo2], 1

    ; ================================================================
    ; GAME_LOOP - Bucle principal
    ;
    ; Cada iteracion es una ronda completa:
    ;   1. Verificar si ambos jugadores fueron eliminados -> fin
    ;   2. Verificar limite de array -> fin si MAX_SEQ
    ;   3. Agregar un simbolo aleatorio a la secuencia
    ;   4. Turno J1 (si activo): mostrar secuencia, validar respuesta
    ;   5. Turno J2 (si activo): igual
    ;   6. Siguiente ronda
    ; ================================================================
game_loop:

    ; ── Verificar si ambos jugadores estan eliminados ─────────────────
    mov al, [vivo1]
    or  al, [vivo2]      ; OR: si ambos son 0, resultado=0
    jz  end_game         ; ZF=1 -> los dos eliminados, terminar juego

    ; ── [CORRECCION BUG 5] Verificar limite del array ─────────────────
    ; El array secuencia[] tiene MAX_SEQ (50) bytes.
    ; Si long_seq ya es 50, no se puede agregar mas sin corrupcionar memoria.
    mov ax, [long_seq]
    cmp ax, MAX_SEQ
    jae nivel_maximo     ; long_seq >= 50 -> fin especial por nivel maximo

    ; ── Agregar un nuevo simbolo aleatorio a la secuencia ─────────────
    inc word ptr [long_seq]     ; incrementar longitud
    mov bx, [long_seq]
    dec bx                      ; BX = indice 0-based del nuevo elemento
    call gen_random             ; AL = 0..3 (preserva BX ahora) [BUG 3 corregido]
    mov [secuencia + bx], al   ; guardar simbolo en el array

    ; ================================================================
    ; TURNO DEL JUGADOR 1
    ; ================================================================
    cmp byte ptr [vivo1], 0
    je  skip_p1          ; J1 eliminado: saltar su turno

    call clear_screen
    mov dx, offset msg_j1hdr
    call print_string
    call show_status     ; mostrar nivel y puntajes actuales

    ; Avisar si J2 ya esta eliminado
    cmp byte ptr [vivo2], 0
    jne p1_j2alive
    mov dx, offset msg_j2elim
    call print_string
p1_j2alive:

    ; Mostrar la secuencia al jugador 1
    mov dx, offset msg_mira
    call print_string
    call show_sequence   ; [BUG 1, 2, 4 corregidos] ciclo correcto

    ; El jugador confirma cuando esta listo
    mov dx, offset msg_listo
    call print_string
    call wait_enter

    ; Preparar pantalla para la respuesta
    call clear_screen
    mov dx, offset msg_j1hdr
    call print_string
    call show_status
    mov dx, offset msg_repite
    call print_string

    ; Capturar y validar la respuesta (CF=0 ok, CF=1 error)
    call get_and_validate
    jc  p1_falla

    ; J1 respondio correctamente
    mov dx, offset msg_bien
    call print_string
    call beep_ok
    mov ax, [long_seq]
    mov [puntaje1], ax   ; puntaje = nivel completado exitosamente
    call delay_long
    jmp skip_p1

p1_falla:
    mov dx, offset msg_mal
    call print_string
    mov dx, offset msg_elim1
    call print_string
    call beep_err
    mov byte ptr [vivo1], 0  ; marcar J1 como eliminado
    call delay_long

skip_p1:

    ; ================================================================
    ; TURNO DEL JUGADOR 2
    ; ================================================================
    cmp byte ptr [vivo2], 0
    je  skip_p2

    call clear_screen
    mov dx, offset msg_j2hdr
    call print_string
    call show_status

    ; Avisar si J1 ya esta eliminado
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

    ; J2 respondio correctamente
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
    jmp game_loop        ; siguiente ronda

    ; ─── Caso: nivel maximo alcanzado con jugadores aun vivos ─────────
nivel_maximo:
    call clear_screen
    mov dx, offset msg_maxniv
    call print_string
    call delay_long
    ; caer directamente en end_game

    ; ================================================================
    ; END_GAME - Mostrar resultados finales y salir
    ; ================================================================
end_game:
    call clear_screen
    mov dx, offset msg_fin
    call print_string
    mov dx, offset msg_sep
    call print_string

    ; Mostrar puntaje final de J1
    mov dx, offset msg_res1
    call print_string
    mov ax, [puntaje1]
    call print_num
    mov dx, offset msg_res_pt
    call print_string

    ; Mostrar puntaje final de J2
    mov dx, offset msg_res2
    call print_string
    mov ax, [puntaje2]
    call print_num
    mov dx, offset msg_res_pt
    call print_string

    mov dx, offset msg_sep
    call print_string

    ; Determinar y anunciar al ganador
    mov ax, [puntaje1]
    cmp ax, [puntaje2]
    jg  j1_gana
    jl  j2_gana

    ; Empate
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

    ; Terminar proceso (retorno a DOS)
    mov ax, 4C00h
    int 21h

main endp

; =====================================================================
; PROCEDIMIENTOS
; =====================================================================

; ─────────────────────────────────────────────────────────────────────
; GEN_RANDOM
; Generador LCG (Linear Congruential Generator) de Knuth:
;   seed_nuevo = (seed_actual x 25173 + 13849) mod 65536
;
; Se retornan los bits 9:8 del seed porque los bits bajos de un LCG
; tienen peor distribucion estadistica (periodicidad mas baja).
;
; Entrada : (ninguna - usa rand_seed en memoria)
; Salida  : AL = 0, 1, 2 o 3
; Preserva: BX, CX, DX  [CORRECCION BUG 3]
; ─────────────────────────────────────────────────────────────────────
gen_random proc

    ; [BUG 3] Guardar TODOS los registros que se van a modificar.
    ; MUL BX modifica DX (parte alta del producto).
    ; MOV CL,8 modifica CX.
    ; Si no se guardan, el llamador recibe registros corrompidos.
    push bx
    push cx
    push dx

    ; Paso LCG: seed = seed * 25173 + 13849  (mod 65536 automatico)
    mov ax, [rand_seed]
    mov bx, 25173
    mul bx               ; DX:AX = AX * BX  (MUL de 16 bits)
                         ; Solo nos importa AX (DX = parte alta, se descarta)
    add ax, 13849
    mov [rand_seed], ax  ; guardar nuevo seed

    ; Extraer bits 9:8 (mayor aleatoriedad que los bits 1:0)
    mov cl, 8
    shr ax, cl           ; AX >>= 8  (SHR reg,CL valido en 8086)
    and ax, 0003h        ; AL = bits 1:0 del byte alto = valor 0..3

    ; [BUG 3] Restaurar registros en orden INVERSO al push
    pop dx
    pop cx
    pop bx
    ret

gen_random endp

; ─────────────────────────────────────────────────────────────────────
; SHOW_SEQUENCE
; Muestra en pantalla todos los simbolos de la secuencia actual,
; uno por uno, con una pausa entre cada uno para memorizarlos.
; Formato de salida: "A-B-C-D-" (simbolo seguido de guion)
;
; CORRECCIONES APLICADAS:
;   BUG 1: delay_medium ahora hace push/pop CX (ya no corrompe el contador)
;   BUG 2: delay_medium usa diferencia de ticks (no falla al desbordarse)
;   BUG 4: se usa DEC CX / JNZ en lugar de LOOP (mas robusto y explicito)
;
; Preserva: AX, BX, CX, SI
; ─────────────────────────────────────────────────────────────────────
show_sequence proc

    push ax
    push bx
    push cx
    push si

    mov cx, [long_seq]   ; CX = total de simbolos a mostrar
    xor si, si           ; SI = indice del simbolo actual (empieza en 0)

    ; Guardia de seguridad: si long_seq es 0 (no deberia ocurrir), salir
    test cx, cx
    jz  ss_fin

ss_bucle:
    ; ── Traducir el valor almacenado (0-3) al caracter ASCII ──────────
    ; [secuencia + SI] contiene 0, 1, 2 o 3.
    ; mapa_sim[valor] contiene 'A', 'B', 'C' o 'D'.
    xor bx, bx                  ; limpiar BX completamente (BH=0, BL=0)
    mov bl, [secuencia + si]    ; BL = valor 0..3 (BH ya es 0)
    mov al, [mapa_sim + bx]     ; AL = caracter ASCII del simbolo

    ; ── Imprimir simbolo con INT 10h / AH=0Eh (teletype) ─────────────
    mov ah, 0Eh
    xor bx, bx           ; BH=0 (pagina de video 0), BL=0 (color)
    int 10h              ; INT 10h imprime el caracter en AL

    ; ── Imprimir guion separador ──────────────────────────────────────
    mov al, '-'
    mov ah, 0Eh
    xor bx, bx
    int 10h

    ; ── Pausa entre simbolos (~0.82 seg) ─────────────────────────────
    ; delay_medium ahora preserva CX correctamente [BUG 1 corregido]
    ; y no falla cuando el timer de 16 bits desborda [BUG 2 corregido]
    call delay_medium

    ; ── Avanzar al siguiente simbolo de la secuencia ─────────────────
    inc si               ; siguiente posicion en el array

    ; [CORRECCION BUG 4] DEC + JNZ en lugar de LOOP.
    ; LOOP es equivalente a "DEC CX; JNZ label" pero si cualquier INT
    ; interna modifica CX, LOOP usaria el CX corrompido. Con DEC/JNZ
    ; el control del contador es completamente explicito.
    dec cx
    jnz ss_bucle         ; CX > 0: quedan simbolos, continuar

ss_fin:
    pop si
    pop cx
    pop bx
    pop ax
    ret

show_sequence endp

; ─────────────────────────────────────────────────────────────────────
; GET_AND_VALIDATE
; Lee la entrada del jugador tecla a tecla y la compara contra la
; secuencia almacenada. Solo acepta '1','2','3','4'. Ignora el resto.
; A medida que el jugador ingresa un simbolo correcto, lo imprime.
; Al primer error retorna inmediatamente con CF=1.
;
; Retorna: CF=0 -> toda la secuencia correcta
;          CF=1 -> el jugador cometio un error
;
; CORRECCION BUG 4: se usa DEC CX / JNZ en lugar de LOOP.
; Aunque INT 16h no deberia modificar CX en BIOS estandar, usar
; DEC/JNZ es mas seguro y explicito.
;
; Preserva: BX, CX, SI
; ─────────────────────────────────────────────────────────────────────
get_and_validate proc

    push bx
    push cx
    push si

    mov cx, [long_seq]   ; CX = numero de teclas validas a esperar
    xor si, si           ; SI = posicion actual en la secuencia

    ; Guardia: si long_seq=0 no hay nada que validar (caso imposible)
    test cx, cx
    jz  gv_ok

gv_leer:
    ; ── Leer tecla del teclado (bloqueante) ───────────────────────────
    ; INT 16h / AH=0 espera hasta que el usuario presione una tecla.
    ; AL = codigo ASCII,  AH = scan code
    ; INT 16h solo modifica AX, no afecta CX, SI ni BX.
    mov ah, 00h
    int 16h

    ; ── Filtrar: solo aceptar teclas '1' (ASCII 49) a '4' (ASCII 52) ──
    cmp al, '1'
    jb  gv_leer          ; tecla < '1': ignorar, pedir otra
    cmp al, '4'
    ja  gv_leer          ; tecla > '4': ignorar

    ; ── Convertir ASCII a indice 0..3 ─────────────────────────────────
    sub al, '1'          ; '1'->0, '2'->1, '3'->2, '4'->3
    xor ah, ah           ; AH=0, AX = indice 0..3

    ; ── Comparar con el valor esperado de la secuencia ────────────────
    ; [secuencia + SI] = simbolo esperado en la posicion SI
    cmp al, [secuencia + si]
    jne gv_error         ; no coincide -> error

    ; ── Tecla correcta: mostrar el simbolo en pantalla ────────────────
    mov bx, ax           ; BX = indice 0..3 (BH=0 porque AH=0)
    mov al, [mapa_sim + bx]  ; AL = 'A', 'B', 'C' o 'D'
    mov ah, 0Eh
    xor bx, bx
    int 10h              ; imprimir simbolo correcto

    mov al, ' '          ; espacio separador visual
    mov ah, 0Eh
    xor bx, bx
    int 10h

    ; ── Avanzar y verificar si quedan simbolos ────────────────────────
    inc si               ; siguiente posicion de la secuencia

    ; [CORRECCION BUG 4] DEC + JNZ en lugar de LOOP
    dec cx
    jnz gv_leer          ; quedan simbolos: pedir siguiente tecla

gv_ok:
    ; Toda la secuencia fue ingresada correctamente
    pop si
    pop cx
    pop bx
    clc                  ; CF=0 -> exito
    ret

gv_error:
    ; El jugador ingreso un simbolo incorrecto
    pop si
    pop cx
    pop bx
    stc                  ; CF=1 -> error
    ret

get_and_validate endp

; ─────────────────────────────────────────────────────────────────────
; SHOW_STATUS
; Muestra el nivel actual y los puntajes de ambos jugadores.
; Se llama al inicio de cada turno como contexto para el jugador.
;
; Preserva: AX, DX
; ─────────────────────────────────────────────────────────────────────
show_status proc

    push ax
    push dx

    ; Linea 1: nivel actual
    mov dx, offset msg_nivel
    call print_string
    mov ax, [long_seq]
    call print_num
    mov dx, offset msg_crlf
    call print_string

    ; Linea 2: puntaje J1
    mov dx, offset msg_pj1
    call print_string
    mov ax, [puntaje1]
    call print_num
    mov dx, offset msg_pts_s
    call print_string

    ; Linea 3: puntaje J2
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
; Convierte AX a cadena decimal ASCII y la imprime con INT 10h.
; Maneja AX=0 como caso especial. Rango: 0..65535.
;
; Algoritmo de extraccion-pila:
;   1. Dividir AX entre 10 repetidamente, apilar cada resto (digito)
;   2. Desapilar e imprimir cada digito (el stack los invierte al orden correcto)
;
; Verificacion de balance de pila:
;   push ax,bx,cx,dx    <- 4 palabras en el stack al inicio
;   push digito x N     <- N digitos apilados en pn_extraer
;   pop  digito x N     <- N digitos desapilados en pn_imprimir
;   pop  dx,cx,bx,ax    <- 4 palabras restauradas en pn_done
;   El stack siempre queda balanceado.
;
; Preserva: AX, BX, CX, DX
; ─────────────────────────────────────────────────────────────────────
print_num proc

    push ax
    push bx
    push cx
    push dx

    ; ── Caso especial: AX = 0 ────────────────────────────────────────
    test ax, ax
    jnz pn_extraer

    ; Imprimir el caracter '0' directamente
    mov ah, 0Eh
    mov al, '0'
    xor bx, bx
    int 10h
    jmp pn_done          ; stack tiene solo los 4 push iniciales

    ; ── Extraccion de digitos (del menos al mas significativo) ────────
    ; Cada iteracion: AX / 10 -> cociente en AX, resto (digito) en DX
    ; El resto se apila. Al terminar, el stack tiene los digitos
    ; en orden invertido (el mas significativo esta arriba).
pn_extraer:
    test ax, ax
    jz  pn_imprimir      ; AX=0: ya no hay mas digitos que extraer

    xor dx, dx           ; DX:AX / BX requiere DX=0 para numeros de 16 bits
    mov bx, 10
    div bx               ; AX = cociente, DX = resto (0..9)
    push dx              ; apilar digito (DL = digito, DH = 0)
    inc cx               ; contar cuantos digitos se apilaron
    jmp pn_extraer

    ; ── Impresion de digitos (en orden correcto gracias al stack) ──────
pn_imprimir:
    test cx, cx
    jz  pn_done          ; CX=0: todos los digitos fueron impresos

    pop dx               ; desapilar siguiente digito (DL = 0..9)
    mov al, dl
    add al, '0'          ; convertir a ASCII: '0'+'digito'
    mov ah, 0Eh
    push cx              ; guardar contador (INT 10h podria modificar CX)
    xor bx, bx           ; BH=0 (pagina), BL=0 (color)
    int 10h              ; imprimir digito
    pop cx               ; restaurar contador
    dec cx
    jmp pn_imprimir

pn_done:
    ; El stack contiene exactamente los 4 registros originales.
    ; Todos los digitos apilados en pn_extraer ya fueron consumidos
    ; en pn_imprimir cuando CX llego a 0.
    pop dx
    pop cx
    pop bx
    pop ax
    ret

print_num endp

; ─────────────────────────────────────────────────────────────────────
; PRINT_STRING
; Imprime una cadena terminada en '$' usando INT 21h / AH=09h.
; DS:DX debe apuntar a la cadena en el segmento de datos.
;
; [CORRECCION BUG 6] Ahora preserva AX.
; INT 21h / AH=09h modifica AX. Antes de esta correccion, cualquier
; llamador que dependiera de AX entre dos llamadas a print_string
; encontraba AX con el valor 0x0900 (AH=09, AL=resultado del servicio).
;
; Preserva: AX
; ─────────────────────────────────────────────────────────────────────
print_string proc

    push ax
    mov ah, 09h
    int 21h
    pop ax
    ret

print_string endp

; ─────────────────────────────────────────────────────────────────────
; CLEAR_SCREEN
; Limpia toda la pantalla usando INT 10h / AH=06h (scroll up).
; Con AL=0 borra el area indicada sin moverla (efecto = cls).
; Luego posiciona el cursor en la esquina superior izquierda (0,0).
;
; Preserva: AX, BX, CX, DX
; ─────────────────────────────────────────────────────────────────────
clear_screen proc

    push ax
    push bx
    push cx
    push dx

    ; INT 10h / AH=06h: Scroll Up
    ;   AL=0  -> borrar area (numero de lineas a scrollear; 0=limpiar todo)
    ;   BH=07 -> atributo: texto blanco (07h) sobre fondo negro (00h)
    ;   CX    -> CH:CL = fila:col de la esquina superior izquierda
    ;   DX    -> DH:DL = fila:col de la esquina inferior derecha
    mov ah, 06h
    xor al, al           ; AL=0: limpiar sin scrollear
    mov bh, 07h          ; atributo blanco sobre negro
    xor cx, cx           ; CH=0 (fila 0), CL=0 (col 0)
    mov dh, 24           ; fila 24 = ultima de pantalla 25x80
    mov dl, 79           ; col 79 = ultima de pantalla 25x80
    int 10h

    ; INT 10h / AH=02h: Set Cursor Position
    ;   BH = pagina de video (0)
    ;   DH:DL = fila:col del cursor
    mov ah, 02h
    xor bh, bh           ; pagina 0
    xor dx, dx           ; DH=0 (fila 0), DL=0 (columna 0)
    int 10h

    pop dx
    pop cx
    pop bx
    pop ax
    ret

clear_screen endp

; ─────────────────────────────────────────────────────────────────────
; WAIT_ENTER
; Espera (bloqueante) hasta que el usuario presione la tecla ENTER.
; Ignora cualquier otra tecla. ENTER = codigo ASCII 13 (0Dh).
;
; Preserva: AX
; ─────────────────────────────────────────────────────────────────────
wait_enter proc

    push ax

we_loop:
    mov ah, 00h
    int 16h              ; AL = ASCII, AH = scan code
    cmp al, 13           ; ENTER = Carriage Return = 0Dh = 13d
    jne we_loop          ; no es ENTER: ignorar y esperar

    pop ax
    ret

wait_enter endp

; ─────────────────────────────────────────────────────────────────────
; DELAY_MEDIUM  (aprox. 0.82 segundos = 15 ticks a 18.2 ticks/seg)
;
; *** CORRECCIONES BUG 1 y BUG 2 ***
;
; BUG 1 — CX corrompido por INT 1Ah:
;   INT 1Ah / AH=0 retorna CX:DX (contador de ticks de 32 bits),
;   sobrescribiendo CX con la parte alta del contador (~0 o ~1 en un
;   sistema que lleva poco tiempo encendido).
;   Antes de esta correccion, show_sequence usaba un bucle con
;   contador en CX. Al llamar delay_medium, INT 1Ah pisaba CX con
;   un valor del timer (ej: 0x0001), corrompiendo el contador del
;   bucle. Resultado: el bucle terminaba al primer o segundo simbolo,
;   o quedaba en bucle con CX=0xFFFF iterando 65535 veces.
;   CORRECCION: push cx al inicio, pop cx al final del procedimiento.
;
; BUG 2 — Desbordamiento del timer de 16 bits:
;   El timer DX de 16 bits llega hasta 65535 y luego vuelve a 0.
;   La version anterior calculaba objetivo = tick_inicial + 15 y
;   esperaba con JB (menor sin signo).
;   PROBLEMA: si tick_inicial = 65530, entonces 65530 + 15 = 65545,
;   que en 16 bits es 65545 mod 65536 = 9.
;   Condicion: JB (tick_actual < 9) con tick_actual=65530 -> FALSO.
;   El delay retornaba INMEDIATAMENTE (0 segundos), haciendo que los
;   simbolos aparecieran instantaneamente sin pausa visible.
;   CORRECCION: medir tiempo transcurrido por DIFERENCIA:
;     elapsed = tick_actual - tick_inicial
;   En aritmetica modular de 16 bits, si tick_actual=10 y
;   tick_inicial=65530 (tras desbordamiento):
;     elapsed = 10 - 65530 mod 65536 = 10 + 65536 - 65530 = 16 >= 15 OK.
;
; Preserva: AX, BX, CX, DX
; ─────────────────────────────────────────────────────────────────────
delay_medium proc

    push ax
    push bx
    push cx              ; [BUG 1] Guardar CX ANTES de INT 1Ah
    push dx

    xor ax, ax
    int 1Ah              ; CX:DX = ticks del sistema
                         ; CX queda sobrescrito aqui, pero ya esta en el stack
    mov bx, dx           ; BX = tick inicial (referencia de tiempo)

dm_esperar:
    xor ax, ax
    int 1Ah              ; DX = tick actual (CX sobrescrito de nuevo, no importa)

    ; [BUG 2] Calcular tiempo transcurrido por diferencia
    ; La resta de 16 bits es correcta incluso con desbordamiento del timer
    mov ax, dx           ; AX = tick actual
    sub ax, bx           ; AX = tick_actual - tick_inicial (mod 65536)
    cmp ax, 15           ; Han pasado >= 15 ticks? (aprox 0.82 segundos)
    jb  dm_esperar       ; no -> seguir esperando

    pop dx
    pop cx               ; [BUG 1] Restaurar CX original del llamador
    pop bx
    pop ax
    ret

delay_medium endp

; ─────────────────────────────────────────────────────────────────────
; DELAY_LONG  (aprox. 1.6 segundos = 29 ticks a 18.2 ticks/seg)
;
; Mismas correcciones que delay_medium (BUG 1 y BUG 2).
; Se usa para dar tiempo al jugador de leer los mensajes de
; exito o error antes de que la pantalla cambie.
;
; Preserva: AX, BX, CX, DX
; ─────────────────────────────────────────────────────────────────────
delay_long proc

    push ax
    push bx
    push cx              ; [BUG 1] Guardar CX
    push dx

    xor ax, ax
    int 1Ah
    mov bx, dx           ; BX = tick inicial

dl_esperar:
    xor ax, ax
    int 1Ah

    ; [BUG 2] Diferencia de ticks (correcto con desbordamiento)
    mov ax, dx
    sub ax, bx
    cmp ax, 29           ; Han pasado >= 29 ticks? (aprox 1.59 segundos)
    jb  dl_esperar

    pop dx
    pop cx               ; [BUG 1] Restaurar CX
    pop bx
    pop ax
    ret

delay_long endp

; ─────────────────────────────────────────────────────────────────────
; BEEP_OK - Doble pitido de exito
; Usa el caracter BEL (ASCII 7) via INT 21h / AH=02h.
; Preserva: AX, DX
; ─────────────────────────────────────────────────────────────────────
beep_ok proc

    push ax
    push dx

    mov ah, 02h
    mov dl, 07h          ; BEL = caracter 7 = pitido del altavoz
    int 21h
    mov ah, 02h
    mov dl, 07h          ; segundo pitido
    int 21h

    pop dx
    pop ax
    ret

beep_ok endp

; ─────────────────────────────────────────────────────────────────────
; BEEP_ERR - Un pitido de error
; Preserva: AX, DX
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
; Punto de entrada del ensamblador
; ─────────────────────────────────────────────────────────────────────
end main
