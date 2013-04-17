avr-gcc -Os -mmcu=attiny24 -o voltmeter.elf voltmeter.c &&
/opt/cross/avr/bin/avr-objcopy -O ihex voltmeter.elf voltmeter.hex &&
avrdude -p t24 -c usbasp -U flash:w:voltmeter.hex
