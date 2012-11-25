/* Voltmeter mit ATtiny24a
 * Pinout:
 * PA0-PA1 - Messeingang 1+2, PA0 doppelbelegung leds4
 * PA2-PA7 - 7-Segment-Anzeige pin a-f (ACTIVE LOW!!!)
 * PB0 - 7-Segment-Anzeige pin g (ACTIVE LOW!!!) & Button
 * PB1-PB3 - 7-Segment-Anodentreiber */

#include <avr/io.h>
#include <avr/interrupt.h>
#include <avr/sleep.h>
#include <stdbool.h>

const unsigned char plexdelay = 32; //~200Hz
const unsigned short adcdelay = 16; //~5Hz=1562; new style: 25*plexdelay=10Hz
const unsigned short compareValues[2][3] = { {700, 70, 7},
					     {1500, 150, 15} };
bool lastbtnstate = 1;
unsigned char currentChannel = 0;
unsigned char currentSegment = 0;
unsigned char currentCode[6] = {0, 0, 0, 0, 0, 0};
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
	PORTB = 0b00001110; //disable all segments
	switch( currentSegment ) {
		case 3 : currentSegment++; //implement special actions for 4th "segment"/LEDs
			DDRA = 0b11111101; //make PA0 output
			PORTA = 0b11110000 | (1<<((ADMUX&1)+2)); //pulls down transistor at PA0 and enables led on PA2/3 depending on ADMUX
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
	DDRB = ~(1<<PB0); //make PB0 input
	decade = PORTB; //use decade to save PORTB
	PORTB = 1<<PB0; //enable pullup

	if( PINB & 1 ^ lastbtnstate ) { //if button and saved state differ
		lastbtnstate = PINB & 1; //save current state
		if( !lastbtnstate ) { //if button was pressed right now, toggle adc
			ADMUX ^= 1;
			currentChannel = ADMUX & 1;
		}
	}
	PORTB = decade; //restore portb
	DDRB = 0x0f; //make PB0 output again

	while( ADCSRA & (1<<ADSC) ); //wait for conversion to end
	unsigned short adc = ADC;

	for(decade = 0; decade < 3; decade++) {
		number = 0;
		while( adc >= compareValues[currentChannel][decade] ) {
			number++;
			adc -= compareValues[currentChannel][decade];
		}
		if( decade == 0 && number == 0 )
			number=10;
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
		if( wait > adcdelay && !(DDRA & 1) ) {
			doadc();
			wait = 0;
		} else
			wait++;
	}

	return 0;
}
