# 📋 Explicación General del Proyecto

## 🏗️ Arquitectura del programa

El programa sigue el modelo `.model small` tipo EXE de EMU8086, con tres
segmentos bien definidos:

  -----------------------------------------------------------------------
  Segmento                            Contenido
  ----------------------------------- -----------------------------------
  `.stack 200h`                       512 bytes --- suficiente para la
                                      pila de llamadas y datos temporales

  `.data`                             Mensajes, variables del juego,
                                      array de secuencia, mapa de
                                      símbolos

  `.code`                             10 procedimientos completos, todos
                                      documentados
  -----------------------------------------------------------------------

------------------------------------------------------------------------

## 🔄 Flujo de la Lógica del Juego

    MAIN
     ├─ Inicializar DS, pantalla, semilla aleatoria (INT 1Ah)
     └─ GAME_LOOP (por ronda)
          ├─ Si vivo1 OR vivo2 = 0 → END_GAME
          ├─ long_seq++  →  gen_random()  →  secuencia[n] = 0..3
          ├─ [TURNO J1 si vivo1=1]
          │     ├─ show_sequence()  ← con delay_medium entre símbolos
          │     ├─ wait_enter()     ← jugador se prepara
          │     └─ get_and_validate()
          │           ├─ CF=0  →  puntaje1 = long_seq  (éxito)
          │           └─ CF=1  →  vivo1 = 0            (eliminado)
          └─ [TURNO J2 si vivo2=1]  ← misma lógica

------------------------------------------------------------------------

## 🧩 Procedimientos clave

### 🔹 gen_random --- Generador LCG (Knuth)

    seed = (seed × 25173 + 13849) mod 65536
    AL   = bits[9:8] del seed AND 3    ; → 0, 1, 2 ó 3

Se usan los bits 9:8 porque los bits bajos de un LCG tienen peor
aleatoriedad.

------------------------------------------------------------------------

### 🔹 show_sequence

-   Usa SI como índice sobre secuencia\[\]
-   Usa BX para indexar mapa_sim\[\]
-   Cada símbolo se muestra con un retardo delay_medium (\~0.82 s)

------------------------------------------------------------------------

### 🔹 get_and_validate

-   Lee teclas con INT 16h
-   Filtra solo '1'--'4'
-   Convierte a índice 0--3
-   Compara contra secuencia\[SI\]

Resultados: - CF = 0 → Secuencia correcta (CLC) - CF = 1 → Error (STC)

------------------------------------------------------------------------

### 🔹 print_num

-   Convierte AX a decimal:
    -   Divide entre 10 (DIV)
    -   Apila los residuos
    -   Los imprime en orden correcto

------------------------------------------------------------------------

### 🔹 delay_medium / delay_long

-   Basados en INT 1Ah (timer del sistema, \~18.2 ticks/segundo)
-   Funcionamiento:
    1.  Leer tick inicial
    2.  Calcular tick objetivo
    3.  Esperar en loop hasta alcanzarlo

-------------------------------------------------------------