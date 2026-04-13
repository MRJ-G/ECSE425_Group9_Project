main:
    addi x1, x0, 3
    addi x2, x0, 3
    nop
    nop
    nop
    beq  x1, x2, target
    addi x5, x0, 99
target:
    addi x6, x0, 42
stop:
    j stop
