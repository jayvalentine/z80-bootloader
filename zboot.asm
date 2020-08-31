    ; ZBoot, a Z80 Bootloader.
    ; Copyright (c) 2020 Jay Valentine

    INCLUDE "string.inc"

    ; Character definitions
    defc    CR = $0d
    defc    LF = $0a
    defc    NULL = $00

    defc    UART_PORT_DATA = 0b00000001
    defc    UART_PORT_CONTROL = 0b00000000

    PUBLIC  UART_PORT_DATA
    PUBLIC  UART_PORT_CONTROL

    ; RAM variables.
    defc    rx_buf = 0xf000
    defc    tx_buf = 0xf100
    
    defc    rx_buf_head = tx_buf + 256
    defc    rx_buf_tail = rx_buf_head + 1
    defc    tx_buf_head = rx_buf_tail + 1
    defc    tx_buf_tail = tx_buf_head + 1

    defc    ihex_record = tx_buf_tail + 1
    defc    ihex_record_end = ihex_record + 44

    defc    prompt_input = ihex_record_end
    defc    cmd = prompt_input + 64
    defc    argv = cmd + 16

    defc    breakpoint = argv + 64


    ; Syscall table.
syscall_table:
    defw    syscall_swrite
    defw    syscall_sread

breakpoint_handler:
    ; Store HL on stack, get stack top (return address)
    ; in HL.
    ex      (SP), HL

    push    HL
    push    AF
    pop     AF
    pop     HL

    ; Return address is address of breakpoint +1.
    dec     HL

    ; Restore original instruction.
    ld      A, (breakpoint)
    ld      (HL), A

    ; Restore HL.
    ex      (SP), HL

    ; Re-execute replaced instruction.
    ret

syscall_handler:
    push    HL
    push    DE
    ld      DE, syscall_table
    ld      E, A
    
    ld      A, (DE)
    ld      L, A
    inc     DE

    ld      A, (DE)
    ld      H, A
    
    jp      (HL)

interrupt_handler:
    di
    push    HL
    push    DE
    push    BC
    push    AF

    ; Is this an interrupt from the 6850?
    in      A, (UART_PORT_CONTROL)
    bit     7, A
    jp      z, _interrupt_skip2
    
    ; Character received?
    bit     0, A
    jp      z, _interrupt_skip1

    call    serial_read_handler
    jp      _interrupt_handle_ret
_interrupt_skip1:

    ; Ready to transmit character?
    bit     1, A
    jp      z, _interrupt_skip2

    call    serial_write_handler
    jp      _interrupt_handle_ret
_interrupt_skip2:

    ; Not any of the known causes.
    call    unknown_interrupt

_interrupt_handle_ret:
    pop     AF
    pop     BC
    pop     DE
    pop     HL
    ei
    reti

    PUBLIC  breakpoint_handler
    PUBLIC  syscall_handler
    PUBLIC  interrupt_handler

serial_read_handler:
    ; Get current tail of buffer.
    ld      H, $f0
    ld      A, (rx_buf_tail)
    ld      L, A

    ; Read data from UART.
    in      A, (UART_PORT_DATA)

    ; Store received character.
    ld      (HL), A

    ; Increment tail.
    ld      HL, rx_buf_tail
    inc     (HL)

    ret

serial_write_handler:
    ; Get current head and tail of buffer.
    ld      A, (tx_buf_tail)
    ld      L, A

    ld      A, (tx_buf_head)

    ; If equal, we've got nothing to transmit.
    ; In this case, we disable tx interrupts and return.
    cp      L
    jp      nz, _tx

    ld      A, 0b10010110
    out     (UART_PORT_CONTROL), A
    ret
_tx:

    ; Otherwise, we've got something to send.
    ; Bottom half of pointer to head is already in L.
    ; We just need to load the top half into H.
    ld      H, $f1

    ; Load character and send.
    ld      A, (HL)
    out     (UART_PORT_DATA), A

    ; Increment tail.
    ld      HL, tx_buf_tail
    inc     (HL)

    ret

unknown_interrupt:
    ret

    ; Syscall definitions.

    ; 0: swrite: Write character to serial port.
    ;
    ; Parameters:
    ; L     - Byte character to send.
    ;
    ; Returns:
    ; Nothing.
    ;
    ; Description:
    ; Busy-waits until serial port is ready to transmit, then
    ; writes the given character to the serial port.
syscall_swrite:
    pop     DE
    pop     HL

direct_syscall_swrite:
    push    HL
    push    DE

    ; This needs to be an atomic operation; Disable interrupts.
    di

    ; Preserve character to send because we're going to need
    ; L.
    ld      E, L

    ld      A, (tx_buf_head)
    ld      L, A

    ld      A, (tx_buf_tail)

    ; If head and tail are equal, we need to enable interrupts before appending to the buffer.
    cp      L
    jp      nz, _swrite_append

    ; Enable TX interrupts
    ld      A, 0b10110110
    out     (UART_PORT_CONTROL), A

_swrite_append:
    ld      H, $f1
    ld      (HL), E

_swrite_done:
    ld      HL, tx_buf_head
    inc     (HL)

    ei

    pop     DE
    pop     HL
    ret

    ; 1: sread: Read character from serial port.
    ;
    ; Parameters:
    ; None.
    ;
    ; Returns:
    ; Character received from serial port, in A.
    ;
    ; Description:
    ; Busy-waits until serial port receives data,
    ; then returns a single received character.
syscall_sread:
    pop     DE
    pop     HL

direct_syscall_sread:
    push    HL
    ld      H, $f0
    ld      A, (rx_buf_head)
    ld      L, A

    ; Wait for char in buffer.
_sread_wait:
    ld      A, (rx_buf_tail)
    cp      L

    ; If head and tail are equal, there's no data in buffer.
    jp      z, _sread_wait

_sread_available:
    ; Load character in A.
    ld      A, (HL)

    ; Increment head.
    ld      HL, rx_buf_head
    inc     (HL)

    pop     HL
    ret

start:
    ; Initialize stack pointer.
    ld      SP, $ffff

    ; Initialize UART.

    ; Master reset.
    ld      A, 0b00000011
    out     (UART_PORT_CONTROL), A

    ; Configure UART.
    ; UART will run at 57600baud with a 3.6864MHz clock.
    ; Word length of 8 bits + 1 stop.
    ; Interrupts enabled on RX, initially disabled on TX.
    ld      A, 0b10010110
    out     (UART_PORT_CONTROL), A

    ; Initialize RX buffer pointers.
    ld      A, $00
    ld      (rx_buf_head), A
    ld      (rx_buf_tail), A
    ld      (tx_buf_head), A
    ld      (tx_buf_tail), A

    ; Enable interrupts, mode 1.
    im      1
    ei

    PUBLIC  start

main:
    ld      HL, boot_message
    call    print

_main_prompt_loop:
    ld      HL, prompt
    call    print

    ld      HL, prompt_input
    call    getline

    call    parse_cmd

    call    newline

    ld      B, monitor_commands_size
    ld      HL, monitor_commands
_main_prompt_parse_loop:
    ; Load command address in little-endian format.
    ld      E, (HL)
    inc     HL
    ld      D, (HL)
    inc     HL

    ; DE now holds address of command, plus command string.
    ; Save HL and load the command subroutine address into it.
    push    HL

    ld      A, (DE)
    ld      L, A
    inc     DE

    ld      A, (DE)
    ld      H, A
    inc     DE

    ; DE now holds address of string with which to make comparison.

    ; Save command subroutine address.
    push    HL

    ; Compare the string, pointed to by DE,
    ; with the command we got from user, in cmd.
    ld      HL, cmd

    ; Set up parameters for function call.
    push    HL
    push    DE

    call    strcmp

    ; Dispose of stack frame.
    inc     SP
    inc     SP
    inc     SP
    inc     SP

    ld      A, H
    or      L
    jp      z, _prompt_command_found

_prompt_command_next:
    ; Discard subroutine address and restore command address.
    pop     HL
    pop     HL ; Command address.

    djnz    _main_prompt_parse_loop
    
    ; Exhausted list and not found command.
    ld      HL, command_not_found_message
    call    print
    jp      _main_prompt_loop

_prompt_command_found:
    ; Restore subroutine address and execute.
    pop     HL
    jp      (HL)

_prompt_command_ret:
    ; Discard command search address and jump
    ; back to prompt.
    pop     HL
    jp      _main_prompt_loop

    halt
    
cmd_sub_load:
    ld      HL, serial_load_message
    call    print

_cmd_sub_load_data:
    call    get_ihex_record

    cp      A, $00
    jp      nz, _cmd_sub_load_data

    call    newline

    jp      _prompt_command_ret

cmd_sub_exec:
    call    $8000
    jp      _prompt_command_ret

cmd_sub_break:
    push    DE
    push    HL
    push    BC

    ; Parse breakpoint address.

    ; Upper half.
    ld      HL, argv
    ld      B, (HL)
    inc     HL
    ld      C, (HL)
    inc     HL
    call    hexconvert

    ; If highest bit of A is not set then this
    ; address is invalid for a breakpoint.
    bit     7, A
    jp      z, _cmd_sub_break_invalid_address

    ld      D, A

    ; Lower half.
    ld      B, (HL)
    inc     HL
    ld      C, (HL)
    inc     HL
    call    hexconvert

    ld      E, A

    ; Breakpoint address now in DE.
    
    ; Load the byte at that address and store in breakpoint.
    ld      A, (DE)
    ld      (breakpoint), A

    ; Set breakpoint (RST 40) at DE.
    ld      A, $ef
    ld      (DE), A

    jp      _cmd_sub_break_done

_cmd_sub_break_invalid_address:
    ld      HL, cmd_sub_break_invalid_address_message
    call    print

_cmd_sub_break_done:
    pop     BC
    pop     HL
    pop     DE
    jp      _prompt_command_ret

    ; Given a command string, parses out the command and arguments,
    ; returning the command string pointer in HL and arguments in argv.
parse_cmd:
    push    DE

    ; First token is the command.
    ld      DE, cmd
    call    parse_token

    ; Second token is argv.
    ld      DE, argv
    call    parse_token

_parse_cmd_done:
    pop     DE
    ret

    ; Parses a single space-delimited token out of a string, in HL.
    ; Stores the token in DE. Sets HL to the character in the string after
    ; the parsed token.
parse_token:
    push    DE

    ; Skip any spaces that may be here.
_parse_token_skip_space:
    ld      A, (HL)
    cp      ' '
    jp      nz, _parse_token_nonspace
    inc     HL
    jp      _parse_token_skip_space

    ; HL now points to first non-space character.
_parse_token_nonspace:
_parse_token_store:
    ld      A, (HL)
    cp      0
    jp      z, _parse_token_done
    cp      ' '
    jp      z, _parse_token_done

    ; Not space or null, so store in DE.
    ld      (DE), A
    inc     HL
    inc     DE

    jp      _parse_token_store

_parse_token_done:
    ; Store terminating null in DE.
    ld      A, 0
    ld      (DE), A

    ; Restore DE and return.
    pop     DE
    ret

    ; Gets a CR/LF-terminated line from serial port.
    ; Destination address is in HL.
getline:
    push    HL

_getline_skip_whitespace:
    call    direct_syscall_sread
    cp      CR
    jp      z, _getline_skip_whitespace
    cp      LF
    jp      z, _getline_skip_whitespace

    ; We now have our first valid character in A.
_getline_characters:
    ; Echo.
    push    HL
    ld      L, A
    call    direct_syscall_swrite
    ld      A, L
    pop     HL

    ld      (HL), A
    inc     HL

    call    direct_syscall_sread
    
    cp      CR
    jp      z, _getline_done
    cp      LF
    jp      z, _getline_done

    jp      _getline_characters

    ; Full line now in buffer.
    ; Let's reset our pointer to the start.
_getline_done:
    ; Write terminating null.
    ld      (HL), NULL

    pop     HL
    ret

print:
    ; Short-circuit in the case where we're given just
    ; a null-byte.
    ld      A, (HL)
    cp      $00
    jp      z, _print_done

_print_loop:
    ; Send a character
    ld      A, (HL)
    cp      $00
    jp      z, _print_done

    inc     HL
    push    HL
    ld      L, A
    call    direct_syscall_swrite
    pop     HL

    jp      _print_loop

_print_done:
    ret

get_ihex_record:
    push    DE
    push    HL
    push    BC

    ; Zero the record string.
    ld      HL, ihex_record
    ld      B, ihex_record_end-ihex_record
_get_ihex_zero:
    ld      (HL), NULL
    inc     HL
    djnz    _get_ihex_zero

    ; Get a CR/LF-delimited record.
    ld      HL, ihex_record
    call    getline

    ; Get a character and echo.
    call    _ihex_sub_getchar

    ; Expect first character of a record to be ':'
    cp      ':'
    jp      nz, _get_ihex_record_invalid

    ; Load size of record data into B.
    call    _ihex_sub_getbyte
    ld      B, A

    ; Next is address, in DE.
    call    _ihex_sub_getbyte
    ld      D, A
    call    _ihex_sub_getbyte
    ld      E, A

    ; Now record type. We only handle the following record types currently:
    ; 00 - Data record
    ; 01 - End of file record
    ;
    ; Seeing as this is a 16-bit address space we're unlikely to need the others.
    call    _ihex_sub_getbyte
    cp      0
    jp      z, _get_ihex_record_isdata

    ; Get checksum, but don't do anything with it.
    call    _ihex_sub_getbyte

    ; Print CRLF
    

    ; End record. We're done, so return false.
    ld      A, $00
    jp      _get_ihex_done

_get_ihex_record_isdata:
    ; Get a byte and store at address in DE.
    ; Then increment DE and loop until B is 0.
    call    _ihex_sub_getbyte
    ld      (DE), A
    inc     DE
    djnz    _get_ihex_record_isdata

    ; Get checksum, but don't do anything with it.
    call    _ihex_sub_getbyte

    ; Print CRLF
    call    newline

    ; We've processed data, so another record is required.
    ; Return true.
    ld      A, $01
    jp      _get_ihex_done

_get_ihex_record_invalid:
    ld      HL, record_invalid_message
    call    print
    ld      A, $00

_get_ihex_done:
    pop     BC
    pop     HL
    pop     DE
    ret

_ihex_sub_getchar:
    ld      A, (HL)
    cp      0
    jp      nz, _ihex_sub_getchar_okay

    ; Change return address to error handler.
    pop     HL
    ld      HL, _get_ihex_record_invalid
    push    HL
    ret

_ihex_sub_getchar_okay:
    inc     HL
    ret

_ihex_sub_getbyte:
    push    BC

    call    _ihex_sub_getchar
    ld      B, A

    call    _ihex_sub_getchar
    ld      C, A

    call    hexconvert

    pop     BC
    ret

hexconvert:
    ; First handle the lower half.
    ld      A, C
    call    _hexconvert_sub_getnybble
    ld      C, A

    ; Now handle the upper half. Shift left 4 times
    ; and then OR in the value of the lower half.
    ld      A, B
    call    _hexconvert_sub_getnybble
    sla     A
    sla     A
    sla     A
    sla     A
    or      C

    ret

    ; Helper subroutine. Assumes hex character in A register,
    ; returns that character's value in A.
_hexconvert_sub_getnybble:
    ; Is it a decimal digit?
    cp      ':'
    jp      nc, _hexconvert_sub_isuppercase

    sub     $30
    ret

_hexconvert_sub_isuppercase:
    ; Is it uppercase char?
    cp      'G'
    jp      nc, _hexconvert_sub_islowercase

    sub     $37
    ret

_hexconvert_sub_islowercase:
    ; Let's assume it's lowercase at this point.
    sub     $57
    ret

    ; Helper function to print CRLF.
newline:
    push    HL
    ld      L, CR
    call    direct_syscall_swrite
    ld      L, LF
    call    direct_syscall_swrite
    pop     HL
    ret

prompt:
    defm    "Ready.\r\n> "
    defb    0

command_not_found_message:
    defm    "Command not found.\r\n"
    defb    0

    ; Command table for the monitor.
monitor_commands:
    defw    cmd_load
    defw    cmd_exec
    defw    cmd_break
monitor_commands_end:
    defc    monitor_commands_size = (monitor_commands_end-monitor_commands)/2

cmd_load:
    defw    cmd_sub_load
    defm    "load"
    defb    0
cmd_exec:
    defw    cmd_sub_exec
    defm    "exec"
    defb    0
cmd_break:
    defw    cmd_sub_break
    defm    "break"
    defb    0

boot_message:
    ; Some setup of the display, using ANSI escape sequences.
    defm    "\033[2J"           ; Clear screen
    defm    "\033[1;1H"         ; Cursor to top-left (not all terminal emulators do this when clearing the screen)
    defm    "\033[32;40m"       ; Green text on black background, for that retro feel ;)
    defm    "ZBoot, a Z80 bootloader/monitor by Jay Valentine.\r\n\r\n"
    defb    0

serial_load_message:
    defm    "Waiting for serial transfer...\r\n"
    defb    0

record_invalid_message:
    defm    "Invalid Intel-HEX record.\r\n"
    defb    0

cmd_sub_break_invalid_address_message:
    defm    "Invalid breakpoint address.\r\n"
    defb    0

break_message:
    defm    "Breakpoint hit.\r\n"
    defb    0
