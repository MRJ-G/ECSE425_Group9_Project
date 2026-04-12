#%%
from convert import AssemblyConverter as AC
# instantiate object
# nibble mode means each 32 bit instruction will be devided into groups of 4 bits separated by space in output txt
convert = AC(output_mode = 'f', nibble_mode = True, hex_mode = False)

# Convert a whole .s file to text file
convert("Project_4_Pipelined_Processor/no_hazard_examples/branch_no_hazard.s", "Project_4_Pipelined_Processor/no_hazard_examples/branch_no_hazard_bin.txt")

# %%
