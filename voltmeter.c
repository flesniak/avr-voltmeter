/* Voltmeter mit ATtiny24a
 * Pinout:
 * PA0-PA1 - Messeingang 1+2
 * PA2-PA7 - 7-Segment-Anzeige pin a-f (ACTIVE LOW!!!)
 * PB0-PB2 - 7-Segment-Anodentreiber
 * PB3 - 7-Segment-Anzeige pin g (ACTIVE LOW!!!)
 * TEMP: PB3 unbelegt, PB2 = 7-Segment g */

#include <avr/io.h>
#include <avr/interrupt.h>
#include <avr/sleep.h>
#include <stdbool.h>

const unsigned char plexdelay = 39; //~200Hz
const unsigned short adcdelay = 1562; //~5Hz
const unsigned short compareValues[2][3] = { {700, 70, 7},
					    {1500, 150, 15} };
bool buttonpressed = 0;
unsigned char currentChannel = 0;
unsigned char currentSegment = 0;
unsigned char segment[3] = {0, 0, 0};
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
				  0b11111111 }; //segment off

ISR(TIM0_COMPA_vect) {
	PORTB |= 0b00000011; //disable all segments
	switch( currentSegment ) {
		case 2 : currentSegment = 0;
			break;
		case 3 : currentSegment = 0; //implement special actions for 4th "segment"/LEDs
			break;
		default : currentSegment++;
	}
	PORTA = segmentCode[segment[currentSegment]] << 2;
	PORTB = segment[currentSegment] >> 6-PB2 & (1<<PB2);
	PORTB &= 1 << currentSegment;
}

ISR(TIM1_COMPA_vect) {
	ADCSRA |= 1<<ADSC; //start conversion
	while( ADCSRA & (1<<ADSC) ); //wait for conversion to end
	unsigned short adc = ADC;

	unsigned char decade;
	for(decade=0; decade < 3; decade++) {
		segment[decade] = 0;
		while( adc > compareValues[currentChannel][decade] ) {
			segment[decade]++;
			adc -= compareValues[currentChannel][decade];
		}
	}
}

int main() {
	DDRA = 0b11111100;
	DDRB = 0b00000111;
	PORTA = 0b00111111; //disable pullup on pa0+1, deactivate leds
	PORTB = 0b00000111; //enable pullup on pb2, disable pb3
	ADMUX = 1<<ADEN;
	
	OCR0A = plexdelay; //set compare match value
	OCR1A = adcdelay;
	TIMSK0 = 2; //enable compare match interrupt
	TIMSK1 = 2;
	TCCR0B = 5; //set prescaler 1024
	TCCR1B = 5;

	sei();

	while(1)
		sleep_mode();

	return 0;
}
