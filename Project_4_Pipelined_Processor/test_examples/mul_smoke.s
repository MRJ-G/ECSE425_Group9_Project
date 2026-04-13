main:
    addi x1, x0, 4
    addi x2, x0, 5
    nop
    nop
    mul  x3, x1, x2
stop:
    j stop
