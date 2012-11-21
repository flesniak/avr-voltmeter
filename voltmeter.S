/*
 * Voltmeter.asm
 *
 *  Created: 12.11.2012 15:32:11
 *   Author: Julius
 */ 


; Voltmeter mit ATtiny24a
; Pinout:
; PA0 - Messeingang 1
; PA1 - Messeingang 2
; PA2-PA7 - 7-Segment-Anzeige pin a-f (ACTIVE LOW!!!)
; PB0-PB1 - 2:4 Mux, 0=10er, 1=1er, 2=0.1er, 3=info-leds
; PB2 - Button change 1/2
; PB3 - 7-Segment-Anzeige pin g (ACTIVE LOW!!!)

.arch attiny24
#include <avr/io.h>

plexdelay = 39 ;~200Hz
adcdelayh = 0x06 ;~5Hz
adcdelayl = 0x1a

temp1 = 16
temp2 = 17
temp3 = 18
temp4 = 19
temp5 = 20
temp6 = 21
ten = 22
one = 23
deci = 24
buttonpressed = 25

.text
.global main
	ldi temp1, lo8(RAMEND)
	out _SFR_IO_ADDR(SPL), temp1
	ldi temp1, 0b11111100
	out DDRA, temp1 ; init ddra

	ldi temp1, 0b00001111
	out DDRB, temp1 ;init ddrb

	ldi temp1, 0b00111111
	out PORTA, temp1 ;disable pullup on pa0+1, deactivate leds

	ldi temp1, 0b00001100
	out PORTB, temp1 ;enable pullup on pb2, disable pb3

	ldi temp1, 0
	out ADMUX, temp1
	ldi temp1, plexdelay
	out _SFR_IO_ADDR(OCR0A), temp1 ;Timer0 delay
	ldi temp1, adcdelayh
	out _SFR_IO_ADDR(OCR1AH), temp1 ;Timer1 delay
	ldi temp1, adcdelayl
	out _SFR_IO_ADDR(OCR1AL), temp1 ;Timer1 delay
	ldi temp1, 2
	out _SFR_IO_ADDR(TIMSK0), temp1
	out _SFR_IO_ADDR(TIMSK1), temp1
	ldi temp1, 5
	out _SFR_IO_ADDR(TCCR0B), temp1 ;Timer0 1024 prescaler
	out _SFR_IO_ADDR(TCCR1B), temp1 ;Timer1 1024 prescaler

	ldi temp1, 0b00000111;alle an PORTB angeschlossenen Teile ausschalten
	out PORTB, temp1

	ldi temp1, 0b10000000
	out ADCSRA, temp1

	ldi buttonpressed, 0

	sei

slp:  	sleep
	rjmp slp

.global TIM0_COMPA_vect ;multiplex
	push temp1
	push temp2
	in temp3, PORTB
	ldi temp1, 0b00000011 ;alle Anzeigen erst mal ausschalten
	or temp1, temp3
	out PORTB, temp1
	andi temp3, 0b00000011
	sec
	rol temp3 ;eine 1 von rechts reinschieben, so dass die 0zum naechsten Anzeige geht
	andi temp3, 0b00000011
	cpi temp3, 0b00000011
	breq load_again
	andi temp3, 0b00000011 ;evtl(nein, sogar sicherlich) nach links geschobene 1 toeten 00000010 -> 00000101
	rjmp weiter1
load_again:
	ldi temp3, 0b00000010
weiter1:
	ldi ZH, hi8(codes)
	ldi ZL, lo8(codes)
	ldi temp1, 0b00000011
	eor temp1, temp3 ;letze bits togglen, so dass an der stelle, die ich anzeigen will, eine 1 ist (also xxxxxx01 zehner, xxxxxx10 einer (xxxxx100 deci)
	mov temp2, ten
	lsr temp1 ;eben pruefen, ob 1 rausgeschoben wurde
	brcs weiter4
	mov temp2, one
	;lsr temp1
	;brcs weiter4
	;mov temp2, deci
weiter4:
	lsl temp2 ;Zahl mit 2 multiplizieren wegen Adressierung im Flash
	add ZL, temp2
	brcc weiter3
	inc ZH
weiter3:
	lpm temp2, Z+
	out PORTA, temp2
	lpm temp2, Z
	cbi _SFR_IO_ADDR(PORTB), 2
	andi temp2, 0b00000100
	breq weiter2
	sbi _SFR_IO_ADDR(PORTB), 2
weiter2:
	in temp1, PORTB
	andi temp1, 0b11111100
	or temp1, temp3
	out PORTB, temp1
	ldi temp1, 0 ;timer wieder auf 0 setzen
	out _SFR_IO_ADDR(TCNT0), temp1

	pop temp2
	pop temp1
	reti

.global TIM1_COMPA_vect ;doadc: Taster an PB2, Anoden der LEDs an PA2 und PA3 mit positiver Logik, beide Kathoden an PA0 mit negativer Logik
	in temp1, DDRB
	andi temp1, ~(1<<2)
	out DDRB, temp1
	in temp1, PORTB
	ori temp1, 1<<2
	out PORTB, temp1
	nop
	nop
	nop
	sbic _SFR_IO_ADDR(PINB), 2
	rjmp buttonend
	cpi buttonpressed, 1
	breq buttonend+1
	ldi temp1, 1
	in temp3, ADMUX
	eor temp3, temp1 ;toggle ADMUX bit 1 -> switch ADC channel
	out ADMUX, temp3
	ldi buttonpressed, 1
	rjmp PC+2
buttonend:
	ldi buttonpressed, 0
	in temp1, DDRB
	ori temp1, 1<<2
	out DDRB, temp1
	in temp1, PORTB
	andi temp1, ~(1<<2)
	out PORTB, temp1

	in temp1, ADCSRA
	ori temp1, 0b01000000
	out ADCSRA, temp1 ;start conversion
adcloop:
	sbic _SFR_IO_ADDR(ADCSRA), 6
	rjmp adcloop ;loop until conversion is complete

	in temp2, ADCL
	in temp1, ADCH

	ldi ZH, hi8(compare)
	ldi ZL, lo8(compare)
	andi temp3, 1
	cpi temp3, 1
	brne PC+2
	adiw ZL, 6
	lpm temp3, Z+
	lpm temp4, Z+

	ldi ten, 0
	cp temp1, temp3
	breq PC+3 ; Messung koennte groesser/gleich 700 sein, je nach low-anteil
	brcc ten1 ; temp1 > temp3 -> Spannung war sicher groesser als 700 (in Zusammenhang mit voriger Zeile)
	brcs jmp1 ;branch if carry set -> temp1 < high(10 10111100)
	cp temp2, temp4
	breq PC+2
	brcs jmp1 ;branch if carry set -> temp2 < low(10 10111100)
ten1:
	sub temp2, temp4
	sbc temp1, temp3
	inc ten

jmp1: 	lpm temp3, Z+
	lpm temp4, Z+
	ldi one, 0
csub1:	cpi temp1, 0
	brne onesub
	cp temp2, temp4
	brcs jmp2 ;branch if temp2 < 70
onesub:	sub temp2, temp4
	sbci temp1, 0
	inc one
	rjmp csub1

jmp2: 	lpm temp3, Z+
	lpm temp4, Z+
	ldi deci, 0
csub2:	cp temp2, temp4
	brcs jmp3 ;branch if temp2 < 70
	sub temp2, temp4
	inc deci
	rjmp csub2

jmp3: 	ldi temp1, 0
	out _SFR_IO_ADDR(TCNT1H), temp1
	out _SFR_IO_ADDR(TCNT1L), temp1
	reti

;.section .progmem.data
codes:
.byte 0b00000000 ;0 PORTA
.byte 0b00000100 ;0 PORTB
.byte 0b11100100
.byte 0b00000100 ;1
.byte 0b10010000
.byte 0b00000000 ;2
.byte 0b11000000
.byte 0b00000000 ;3
.byte 0b01100100
.byte 0b00000000 ;4
.byte 0b01001000
.byte 0b00000000 ;5
.byte 0b00001000
.byte 0b00000000 ;6
.byte 0b11100000
.byte 0b00000100 ;7
.byte 0b00000000
.byte 0b00000000 ;8
.byte 0b01000000
.byte 0b00000000 ;9
.byte 0b11111100
.byte 0b00000100 ;display off

compare:
.byte 700 >> 8
.byte 700 & 0xf ;15V ten
.byte 0
.byte 70 ;15V one
.byte 0
.byte 7 ;15V deci

.byte 1500 >> 8
.byte 1500 & 0xf ;5V ten dummy
.byte 0
.byte 150 ;5V one
.byte 0
.byte 15 ;5V deci

.end