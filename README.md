# fdtd2d
FPGA implementation (Verilog) of 2D finite difference time domain (FDTD) simulation of Maxwells equations relating electricity and magnetism.

# platform
Using the 10M25 fpga platform as a starting base infrastruture of:HDMI graphics, text, perf meters, git commit_id overlay).

Plan: integrate FTDI simulation using a nxm compute block 
operating on a NxM sized array. M9K block rams as coeff storage holding
18-bit fixed point E and H feild data. EM equations in hardware for array processing on the FTDT Yee grid.
EM source (dipole) is hardwired in logic, along with boundary handling (reflect, periodic, PML).
HDMI display the EM array with shades of blue/green/red and possible
cross section plots. Allow single step push button to check for sensible operation
and then full rate testing. Goal is to see the waves and acheive maximum performance.
Extrapolate the learning to other devices to see if something interesting can be acheived.



