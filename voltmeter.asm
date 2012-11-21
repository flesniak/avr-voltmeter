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
;
;.include "/opt/cross/avr/avr/include/avr/iotn24a.h"

.equ plexdelay = 39  ;~200Hz
.equ adcdelay = 1562 ;~5Hz

.def temp1 = r16
.def temp2 = r17
.def temp3 = r18
.def temp4 = r19
.def temp5 = r20
.def temp6 = r21
.def ten = r22
.def one = r23
.def deci = r24
.def buttonpressed = r25

.org 0x0000
      rjmp main
.org OC1Aaddr
      rjmp doadc
.org OC0Aaddr
      rjmp multiplex


main: 
	  ldi temp1, LOW(RAMEND)
	  out SPL, temp1
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
      out OCR0A, temp1 ;Timer0 delay
      ldi temp1, HIGH(adcdelay)
      out OCR1AH, temp1 ;Timer1 delay
      ldi temp1, LOW(adcdelay)
      out OCR1AL, temp1 ;Timer1 delay
	  ldi temp1, 2
	  out TIMSK0, temp1
	  out TIMSK1, temp1
      ldi temp1, 5
      out TCCR0B, temp1 ;Timer0 1024 prescaler
      out TCCR1B, temp1 ;Timer1 1024 prescaler

	  ldi temp1, 0b00000111;alle an PORTB angeschlossenen Teile ausschalten
	  out PORTB, temp1

	  ldi temp1, 0b10000000
	  out ADCSRA, temp1

	  ldi buttonpressed, 0

	  sei

slp:  sleep
      rjmp slp


multiplex:
		push temp1
		push temp2
		in temp3, PORTB
		ldi temp1, 0b00000011;alle Anzeigen erst mal ausschalten
		or temp1, temp3
		out PORTB, temp1
		andi temp3, 0b00000011
		sec
		rol temp3;eine 1 von rechts reinschieben, so dass die 0zum naechsten Anzeige geht
		andi temp3, 0b00000011
		cpi temp3, 0b00000011
		breq load_again
		andi temp3, 0b00000011;evtl(nein, sogar sicherlich) nach links geschobene 1 toeten 00000010 -> 00000101
		rjmp weiter1
load_again:
		ldi temp3, 0b00000010
weiter1:
		ldi ZH, HIGH(2*codes)
		ldi ZL, LOW(2*codes)
		ldi temp1, 0b00000011
		eor temp1, temp3;letze bits togglen, so dass an der stelle, die ich anzeigen will, eine 1 ist (also xxxxxx01 zehner, xxxxxx10 einer (xxxxx100 deci)
		mov temp2, ten
		lsr temp1;eben pruefen, ob 1 rausgeschoben wurde
		brcs weiter4
		mov temp2, one
		;lsr temp1
		;brcs weiter4
		;mov temp2, deci
weiter4:
		lsl temp2;Zahl mit 2 multiplizieren wegen Adressierung im Flash
		add ZL, temp2
		brcc weiter3
		inc ZH
weiter3:
		lpm temp2, Z+
		out PORTA, temp2
		lpm temp2, Z
		cbi PORTB, 2
		andi temp2, 0b00000100
		breq weiter2
		sbi PORTB, 2
weiter2:
		in temp1, PORTB
		andi temp1, 0b11111100
		or temp1, temp3
		out PORTB, temp1
		ldi temp1, 0;timer wieder auf 0 setzen
		out TCNT0, temp1

		pop temp2
		pop temp1
		reti

doadc:;Taster an PB2, Anoden der LEDs an PA2 und PA3 mit positiver Logik, beide Kathoden an PA0 mit negativer Logik
      in temp1, DDRB
	  andi temp1, ~(1<<2)
	  out DDRB, temp1
	  in temp1, PORTB
	  ori temp1, 1<<2
	  out PORTB, temp1
	  nop
	  nop
	  nop
	  sbic PINB, 2
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
      sbic ADCSRA, 6
      rjmp adcloop ;loop until conversion is complete

      in temp2, ADCL
      in temp1, ADCH
	  
	  ldi ZH, HIGH(2*compare)
	  ldi ZL, LOW(2*compare)
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

jmp1: lpm temp3, Z+
	  lpm temp4, Z+
      ldi one, 0
csub1:cpi temp1, 0
	  brne onesub
	  cp temp2, temp4
      brcs jmp2 ;branch if temp2 < 70
onesub:sub temp2, temp4
	  sbci temp1, 0
      inc one
      rjmp csub1

jmp2: lpm temp3, Z+
	  lpm temp4, Z+
	  ldi deci, 0
csub2:cp temp2, temp4
      brcs jmp3 ;branch if temp2 < 70
      sub temp2, temp4
      inc deci
      rjmp csub2

jmp3: ldi temp1, 0
      out TCNT1H, temp1
	  out TCNT1L, temp1
      reti

;   PORTA     , PORTB
codes:
.db 0b00000000, 0b00000100 ;0
.db 0b11100100, 0b00000100 ;1
.db 0b10010000, 0b00000000 ;2
.db 0b11000000, 0b00000000 ;3
.db 0b01100100, 0b00000000 ;4
.db 0b01001000, 0b00000000 ;5
.db 0b00001000, 0b00000000 ;6
.db 0b11100000, 0b00000100 ;7
.db 0b00000000, 0b00000000 ;8
.db 0b01000000, 0b00000000 ;9
.db 0b11111100, 0b00000100 ;display off

compare:
.db high(700), low(700) ;15V ten
.db 0, 70 ;15V one
.db 0, 7 ;15V deci
.db high(1500), low(1500) ;5V ten dummy
.db 0, 150 ;5V one
.db 0, 15 ;5V deci