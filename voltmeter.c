/* Voltmeter mit ATtiny24a
 * Pinout:
 * PA0-PA1 - Messeingang 1+2, PA0 doppelbelegung leds4
 * PA2-PA7 - 7-Segment-Anzeige pin a-f (ACTIVE LOW!!!)
 * PB0 - 7-Segment-Anzeige pin g (ACTIVE LOW!!!) & Button
 * PB1-PB3 - 7-Segment-Anodentreiber
 * Flashen: avrdude -p t24 -c usbasp -U flash:w:voltmeter.hex
 * Fuses: avrdude -p t24 -c usbasp -U lfuse:w:0xe2:m -U hfuse:w:0x5f:m */

#include <avr/io.h>
#include <avr/interrupt.h>
#include <avr/sleep.h>
#include <stdbool.h>

const unsigned char plexdelay = 32; //~244Hz = 8MHz/1024/plexdelay
const unsigned char adcdelay = 16; //~15Hz = plexdelay/adcdelay
const unsigned short compareValues[2][3] = { {700, 70, 7}, //0..14,3V
                                             {700, 70, 7} }; //0..14,3V
//					     {1500, 150, 15} }; //0..6,8V

bool lastbtnstate = 0;
unsigned char currentChannel = 0;
unsigned char currentSegment = 0;
unsigned char currentCode[6] = {0, 0, 0, 0, 0, 0};
/*                                  1gfedcba
unsigned char segmentCode[11] = { 0b11000000, //0
				  0b11111001, //1
				  0b10100100, //2
				  0b10110000, //3
				  0b10011001, //4
				  0b10010010, //5
				  0b10000010, //6
				  0b11111000, //7
				  0b10000000, //8
				  0b10010000, //9
				  0b11111111 }; */ //segment off
				  //1decbfag
unsigned char segmentCode[12] = { 0b01111110, //0
                                  0b00011000, //1
                                  0b01101011, //2
                                  0b01011011, //3
                                  0b00011101, //4
                                  0b01010111, //5
                                  0b01110111, //6
                                  0b00011010, //7
                                  0b01111111, //8
                                  0b01011111, //9
                                  0b00000000, //segment off
                                  0b11100111 }; //Error 'E'

ISR(TIM0_COMPA_vect) {
	PORTB = 0b00001110; //disable all segments
	switch( currentSegment ) {
		case 3 : currentSegment++; //implement special actions for 4th "segment"/LEDs
                        PORTA = 0;
			DDRA = 0b11111001; //make PA0 output, PA2 input for button
			PORTA = (1<<((ADMUX&1)?7:3)); //pulls down transistor at PA0 and enables led on PA3/7 depending on ADMUX
			break;
		case 4 : currentSegment = 0;
			DDRA = 0b11111100; //restore normal I/O config, PORTA is done below
		default : PORTA = currentCode[currentSegment*2];
			PORTB = ~(1 << (currentSegment+1)) & 0b00001110 | currentCode[currentSegment*2+1];
			currentSegment++;
	}
	TCNT0 = 0;
}

void doadc() {
	TCCR0B = 0;
	ADCSRA |= 1<<ADSC; //start conversion, afterwards do button stuff to save time
	unsigned char decade, number;
        /*decade = PORTA; //use decade to save PORTA
	DDRA &= ~(1<<PA2); //make PA2 input
	PORTA |= 1<<PA2; //enable pullup on PA2 (where button resides)

	if( (PINA >> 3 & 1) ^ lastbtnstate ) { //if button and saved state differ
		lastbtnstate = !lastbtnstate; //save current state
		if( !lastbtnstate ) { //if button was pressed right now, toggle adc
			ADMUX ^= 1;
			currentChannel = ADMUX & 1;
		}
	}
	PORTA = decade; //restore portb
	DDRA = 0b11111100; //make PB0 output again*/

	while( ADCSRA & (1<<ADSC) ); //wait for conversion to end
	unsigned short adc = ADC;

        if( adc > 1016 ) { //Error threshold
          currentCode[0] = segmentCode[11] << 2;
          currentCode[1] = segmentCode[11]>> 6 & 1;
          currentCode[2] = segmentCode[11] << 2;
          currentCode[3] = segmentCode[11]>> 6 & 1;
          currentCode[4] = segmentCode[11] << 2;
          currentCode[5] = segmentCode[11]>> 6 & 1;
        } else
          for(decade = 0; decade < 3; decade++) {
                  number = 0;
                  while( adc >= compareValues[currentChannel][decade] ) {
                          number++;
                          adc -= compareValues[currentChannel][decade];
                  }
                  if( decade == 0 && number == 0 )
                          number=10; //display nothing instead of zero if U<10V
                  currentCode[2*decade] = segmentCode[number] << 2;
                  currentCode[2*decade+1] = segmentCode[number] >> 6 & 1; //get bit 6, move it to PB0 (segment g)
          }

	TCCR0B = 5;
}

int main() {
	DDRA = 0b11111100;
	DDRB = 0b00001111;
	PORTA = 0b11111100; //disable pullup on PA0+1, deactivate leds
	PORTB = 0b00001111; //PB1-PB3 are multiplexer outputs, PB0 is for g segment->deactivate
	ADCSRA = 1<<ADEN;
	ADMUX = 0;

	OCR0A = plexdelay; //set compare match value
	TIMSK0 = 2; //enable compare match interrupt
	TCCR0B = 5; //set prescaler 1024

	sei();

	unsigned char wait = 0;
	while(1) {
		sleep_mode();
		//if( (currentCode[2*currentSegment+1] & (6-PB3)) && !(DDRA & 1) && wait > adcdelay ) {
                if( !(DDRA & 4) ) {
                  if( (PINA >> 2 & 1) ^ lastbtnstate ) { //if button and saved state differ
                    lastbtnstate = !lastbtnstate; //save current state
                    if( lastbtnstate ) { //if button was pressed right now, toggle adc
                      ADMUX ^= 1;
                      currentChannel = ADMUX & 1;
                    }
                  }
                }
                if( wait > adcdelay && !(DDRA & 1) ) {
			doadc();
			wait = 0;
                } else
                        wait++;
	}

	return 0;
}
