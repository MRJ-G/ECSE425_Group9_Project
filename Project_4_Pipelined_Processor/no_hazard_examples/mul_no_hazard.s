main:
    addi x1, x0, 6
    addi x2, x0, 7
    nop
    nop
    mul  x3, x1, x2
    nop
    nop
    addi x4, x3, 1
stop:
    j stop
