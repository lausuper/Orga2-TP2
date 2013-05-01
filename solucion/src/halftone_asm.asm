; void halftone_asm (
;   unsigned char *src,
;   unsigned char *dst,
;   int m,
;   int n,
;   int src_row_size,
;   int dst_row_size
; );

; Parámetros:
;   rdi = src
;   rsi = dst
;   rdx = m
;   rcx = n
;   r8 = src_row_size
;   r9 = dst_row_size

%define Tiene_Ultimo_Tramo 1
%define No_Tiene_ultimo_tramo 0

extern halftone_c

global halftone_asm

section .rodata

mascara_impares: DQ 0x0011001100110011,0x0011001100110011
mascara_pares: DQ 0x1100110011001100,0x1100110011001100

section .text

halftone_asm:
	PUSH rbp 			; Alineado
	MOV rbp,rsp
	PUSH rbx 			; Desalineado
	PUSH r12 			; Alineado
	PUSH r13 			; Desalineado
	PUSH r14 			; Alineado
	PUSH r15 			; Desalineado

	; guardo valores
	MOV r13,rdx 			; r13d = m
	SAR r13,1				; r13d = m/2 esto es porque voy de a dos lineas a la vez

	; guardo el valor del padding
	MOV r10,r8
	MOV r11,r9
	SUB r10,rcx
	SUB r11,rcx

	; ////////////////////////////////////////////////////////////////////////////////
	; //////////////////////// SETEO DATOS DE USO GENERAL ///////////////////////////
	; ////////////////////////////////////////////////////////////////////////////////

	; obtengo la cantidad de veces que puedo avanzar en una fila
	XOR edx,edx
	MOV r12,16
	MOV eax,ecx
	IDIV r12 				; eax = parte entera(n/16), edx = resto de la divicion
	MOV r14,rax 			; r14d = parte entera(n/16)
	MOV rbx,r14 			; r11d = parte entera de(n/16)
	


	; me fijo si es resto fue 0 o noy lo seteo en un flag.
	MOV r12,No_Tiene_ultimo_tramo
	CMP rdx,0
	JE .setear_registros

	; si no salto es porque hay un tramo mas a recorrer
	; me guardo el valor de lo que hay que restarle a la ultima posicion valida para obtener el ultimo tramo
	MOV r15,16			
	SUB r15,rdx
	MOV r12,Tiene_Ultimo_Tramo 	; seteo el falg indicando que si hay un ultimo tramo

.setear_registros:

	; seteo todos los datos necesarios una sola vez para todos los ciclos
	; registros xmm12-xmm15 con los valores 205,410,615,820 respectivamente
	
	MOV rax,205
	MOVQ xmm12,rax
	PSHUFLW xmm12,xmm12,0
	MOVDQU xmm9,xmm12
	PSLLDQ xmm9,8
	POR xmm12,xmm9

	MOV rax,410
	MOVQ xmm13,rax
	PSHUFLW xmm13,xmm13,0
	MOVDQU xmm9,xmm13
	PSLLDQ xmm9,8
	POR xmm13,xmm9
	
	MOV rax,615
	MOVQ xmm14,rax
	PSHUFLW xmm14,xmm14,0
	MOVDQU xmm9,xmm14
	PSLLDQ xmm9,8
	POR xmm14,xmm9

	MOV rax,820
	MOVQ xmm15,rax
	PSHUFLW xmm15,xmm15,0
	MOVDQU xmm9,xmm15
	PSLLDQ xmm9,8
	POR xmm15,xmm9

	MOVDQU xmm11,[mascara_impares]
	MOVDQU xmm10,[mascara_pares]

	; ////////////////////////////////////////////////////////////////////////////////
	; /////////////////// COMIENZA EL CICLO PARA RECORRER LA IMAGEN //////////////////
	; ////////////////////////////////////////////////////////////////////////////////

.ciclo:	CMP r13,0 				; en r13d esta la cantidad de filas que me faltan recorrer
		JE .fin 				; si termino de recorrer la imagen salgo de la funcion

		; ////////////////////////////////////////////////////////////////////////////////
		; ///////////////ACA COMIENZA EL PROCESAMIENTO EN PARALELO ///////////////////////
		; ////////////////////////////////////////////////////////////////////////////////

		; obtengo los datos en memoria
		MOVDQU xmm0,[rdi] 		; obtengo los primeros 16 bytes de la linea actual
		MOVDQU xmm2,[rdi+r8]	; obtengo los primeros 16 bytes de la siguiente linea, r8d = rsc_row_size

		; ////////////////////////////////////////////////////////////////////////////////
		; ///////////////////////////////// DESEMPAQUETO /////////////////////////////////
		; ////////////////////////////////////////////////////////////////////////////////

		; muevo la parte baja de los registros a otros para no perderlos ya que al desempaquetar necesito 
		; el doble de lugar
		MOVQ xmm1,xmm0 			; en xmm1 obtengo la parte baja de xmm0 puesto en la parte baja de xmm1
		MOVQ xmm3,xmm2 			; en xmm3 obtengo la parte baja de xmm2 puesto en la parte baja de xmm3

		PXOR xmm5,xmm5 			; seteo en 0 xmm5 esto es para extender el numero con 0's

		; desempaqueto en los registros xmm0,xmm1 los datos de la primera linea
		PUNPCKHBW xmm0,xmm5
		PUNPCKLBW xmm1,xmm5

		; desempaqueto en los registros xmm2,xmm3 los datos de la segunda linea
		PUNPCKHBW xmm2,xmm5
		PUNPCKLBW xmm3,xmm5

		; ////////////////////////////////////////////////////////////////////////////////
		; ////////////////////// SUMO LOS VALORES DE LOS CUADRADOS ///////////////////////
		; ////////////////////////////////////////////////////////////////////////////////

		; sumo los word en paralelo, aca tengo la suma parcial que queda guardada en xmm0,xmm1
		PADDW xmm0,xmm2
		PADDW xmm1,xmm3

		; luego sumo de a dos word's de forma horizontal obteniendo en xmm0 la suma de cada 
		; uno de los cuadrados que queria 
		PHADDW xmm1,xmm0

		; ////////////////////////////////////////////////////////////////////////////////
		; //////////////////////////// ARMO LA MASCARA ///////////////////////////////////
		; ////////////////////////////////////////////////////////////////////////////////

		; primer caso: t < 205
		MOVDQU xmm0,xmm1
		PCMPGTW xmm0,xmm12

		; le pongo 0's a los lugares que no le corresponden. Estos son los lugares pares de la primera fila xmm0, ya que 
		; si t > 205 en el lugar (1,1) el cuadrado seguro es blanco, 255 = 0x11111111
		PAND xmm0,xmm10

		; segundo caso t > 410
		MOVDQU xmm2,xmm1
		PCMPGTW xmm2,xmm13

		; le pongo 0's a los lugares que no le corresponden
		PAND xmm2,xmm11 

		; tercer caso t > 615
		MOVDQU xmm3,xmm1
		PCMPGTW xmm3,xmm14

		; le pongo 0's a los lugares que no le corresponden
		PAND xmm3,xmm10 

		; cuarto caso t > 820
		PCMPGTW xmm1,xmm15

		; le pongo 0's a los lugares que no le corresponden
		PAND xmm1,xmm11

		; junto los resultados de la primera linea que esta actualmente en xmm0,xmm1 vertiendolo todo en xmm0
		POR xmm0,xmm1

		; lo mismo para la segunda fila que esta en xmm2,xmm3
		POR xmm2,xmm3

		; TENGO UNA MASCARA DE LA PRIMERA LINEA Y LA SEGUNDA DONDE HAY 0's EN LOS LUGARES DONDE VA NEGRO Y 1's EN
		; LOS LUGARES DONDE VA BLANCO, DA LA CASUALIDAD QUE NEGRO ES 0 = 0x00000000 Y BLANCO ES 255 = 0x11111111
		; POR LO QUE NO TENGO QUE HACER MAS NADA Y LA MASCARA ES EXACTAMENTE EL RESULTADO

		; ////////////////////////////////////////////////////////////////////////////////
		; ////////////// GUARDO LOS DATOS EN LOS LUGARES DE DESTINO //////////////////////
		; ////////////////////////////////////////////////////////////////////////////////
		
		MOVDQU [rsi],xmm0
		MOVDQU [rsi+r9],xmm2

		; ////////////////////////////////////////////////////////////////////////////////
		; ///////////////ACA TERMINA EL PROCESAMIENTO EN PARALELO ////////////////////////
		; ////////////////////////////////////////////////////////////////////////////////

		; ////////////////////////////////////////////////////////////////////////////////
		; /////////////// CODIGO PARA RECORRER LA MATRIZ DE LA IMAGEN ////////////////////
		; ////////////////////////////////////////////////////////////////////////////////

		DEC rbx 					; decremento la cantidad de iteraciones que me faltan para terminar la fila actual

		; me fijo si ya llegue al final de la fila
		CMP rbx,0
		JE .termine_iteraciones ; en el caso en que halla llegado al final debo ver si tengo que recorrer el proximo 
								; tramito o no

		; me fijo si mire el ultimo tramo
		CMP rbx,-1
		JE .saltear_proxima_linea

		; si no termine las iteraciones entonces solo sumo 16 para pasar al proximo ciclo
	.siguienteLinea:
		ADD rdi,16
		ADD rsi,16
		JMP .finCiclo

		; si termine las iteraciones entonces me fijo si tengo que saltar directamente a la proxima fila o si queda un tramo menor a 16 por recorrer
	.termine_iteraciones:
		CMP r12,No_Tiene_ultimo_tramo
		JE .saltear_proxima_linea 		; si no hay ultimo tramo salto directamente a la proxima fila a procesar 

		; si no salto es porque puede haber un ultimo tramo a recorrer
		; en tal caso me fijo si ya lo hice o no
		SUB rdi,r15
		SUB rsi,r15
		JMP .finCiclo

	.saltear_proxima_linea:
		MOV rbx,r14 				; le vuelvo a cargar la cantidad de iteraciones a realizar en una lina
		ADD rdi,16
		ADD rsi,16	
		LEA rdi,[rdi + r10] 	; le cargo el padding
		LEA rsi,[rsi + r11]
		ADD rdi,r8 					; me saleteo la lina ya que debo ir de dos en dos
		ADD rsi,r9
		DEC r13 					; decremento el contador de lineas restantes


.finCiclo:
	JMP .ciclo 			; paso a la próxima iteración 	

.fin:
	POP r15
	POP r14
	POP r13
	POP r12
	POP rbx
	POP rbp
	RET