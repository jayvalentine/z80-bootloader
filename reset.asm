    EXTERN  start
    
    ; Entry point.
reset:
    ; Disable interrupts on startup.
    di
    jp      start
