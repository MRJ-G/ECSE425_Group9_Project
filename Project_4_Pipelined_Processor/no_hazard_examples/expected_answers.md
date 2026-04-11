arith_mem_no_hazard
- x1 = 5
- x2 = 7
- x3 = 12
- x4 = 12
- x5..x31 = 0
- memory[0] = 12
- memory[1..8191] = 0

branch_no_hazard
- x1 = 3
- x2 = 3
- x5 = 0 (beq taken, skipped)
- x6 = 42
- all other registers = 0
- memory[0..8191] = 0

mul_no_hazard
- x1 = 6
- x2 = 7
- x3 = 42
- x4 = 43
- x5..x31 = 0
- memory[0..8191] = 0