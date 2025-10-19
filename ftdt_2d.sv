// 2D FTDT Compute block
// A parameterized cellular array and memories
// Computer array WIDTH x HEIGHT is processed each cycle. 
// Memory depth = DEPTH


module ftdt_2d #(
	WIDTH = 3,		// Array width = Datapath width
	DEPTH = 256,	// memory Depth, (ignored, always 256 supported, we use M9Ks as 32bit x 256word rams)
	HEIGHT = 3,		// Datapath height
	DBITS = 8,		// depth address bitwidth, (ignored, only 8 supported with M9K rams)
	GENS  = 1,		// Number of EM generations
	FBITS = 18		// EM Feilds vector axis precision (HZx, HZy, EX, EY) in memory
) (
	// System
	input clk,
	input reset,
	// Memory Control
	input logic [2:0][2:0][7:0] raddr, // also used for init writes
	input logic [7:0] waddr,
	input	logic we,
	// Excitation input
	input logic [WIDTH-1:0] excite_col_flag,
	input logic [FBITS-1:0] excitation,
	// PML Col 
	input logic [WIDTH-1:0] pml_col_flag,
	input logic [WIDTH-1:0][2:0] pml_sel, 
	// Ex,Ey
	input logic [WIDTH-1:0][HEIGHT-1:0][FBITS-1:0] alpha_ex,
	input logic [WIDTH-1:0][HEIGHT-1:0][FBITS-1:0] alpha_exex,
	input logic [WIDTH-1:0][HEIGHT-1:0][FBITS-1:0] alpha_ey,
	input logic [WIDTH-1:0][HEIGHT-1:0][FBITS-1:0] alpha_eyey,
	// Hzx, Hzy
	input logic [WIDTH-1:0][HEIGHT-1:0][FBITS-1:0] alpha_hzx,
	input logic [WIDTH-1:0][HEIGHT-1:0][FBITS-1:0] alpha_hzy,
	input logic [WIDTH-1:0][HEIGHT-1:0][FBITS-1:0] alpha_hzxhz,
	input logic [WIDTH-1:0][HEIGHT-1:0][FBITS-1:0] alpha_hzyhz,
	
	
	// External Data Control
	input logic ld,
	output logic [4*FBITS*HEIGHT*WIDTH*-1:0] dout, // snapshot of array
	// Init port
	input logic init,
	input logic init_data
	
);

	/////////////////////////////////////////
	//     Memory and Read
	////////////////////////////////////////
	// Built up from call_ram_36 = M9K as 36bx256w, registered I/O 
	// nine bulk memories for 3x3 neighbour hood of core W*H + 8 Boundasry blocks. 
	// Neighbors represent neighbour location (We swap when writing)	
	// 
	logic [4*FBITS*GENS*GENS   -1+35:0] mem00_din, mem00_dout;  // UL
	logic [4*FBITS*GENS*GENS   -1+35:0] mem02_din, mem02_dout;	// UR
	logic [4*FBITS*GENS*GENS   -1+35:0] mem20_din, mem20_dout;	// LL
	logic [4*FBITS*GENS*GENS   -1+35:0] mem22_din, mem22_dout;	// LR
	logic [4*FBITS*GENS*WIDTH  -1+35:0] mem01_din, mem01_dout;	// Top
	logic [4*FBITS*GENS*WIDTH  -1+35:0] mem21_din, mem21_dout;	// Bot
	logic [4*FBITS*GENS*HEIGHT -1+35:0] mem10_din, mem10_dout;	// Left
	logic [4*FBITS*GENS*HEIGHT -1+35:0] mem12_din, mem12_dout;	// Right
	logic [4*FBITS*WIDTH*HEIGHT-1+35:0] mem11_din, mem11_dout;	// center core
	
	// Register raddr, waddr, we, large large fanout.
	// Synth tool intended to replicate regs as need to meet timing.
	logic [2:0][2:0][7:0] raddr_q; // 1,1 also used for video read
	logic [7:0] 			 waddr_q; // init or life
	logic 					 we_q;	 // init or life
	logic						 init_q;
	always_ff @(posedge clk) begin
		raddr_q 	<= raddr;
		we_q 		<= we;
		waddr_q 	<= waddr; 
		init_q   <= init;
	end

	// Generate sufficient 32bit mems to cover each of the 9 spatial arrays 
	genvar genii, genjj;
	generate 
		for( genii = 0; genii < 4*FBITS*GENS*GENS; genii+=36 ) begin : _mem_corner
			cell_ram36 _ram00 ( .clock( clk ), .data( mem00_din[genii+35-:36] ), .rdaddress( raddr_q[0][0] ), .wraddress( waddr_q ), .wren( we_q ),	.q( mem00_dout[genii+35-:36] ));
			cell_ram36 _ram20 ( .clock( clk ), .data( mem20_din[genii+35-:36] ), .rdaddress( raddr_q[2][0] ), .wraddress( waddr_q ), .wren( we_q ),	.q( mem20_dout[genii+35-:36] ));
			cell_ram36 _ram02 ( .clock( clk ), .data( mem02_din[genii+35-:36] ), .rdaddress( raddr_q[0][2] ), .wraddress( waddr_q ), .wren( we_q ),	.q( mem02_dout[genii+35-:36] ));
			cell_ram36 _ram22 ( .clock( clk ), .data( mem22_din[genii+35-:36] ), .rdaddress( raddr_q[2][2] ), .wraddress( waddr_q ), .wren( we_q ),	.q( mem22_dout[genii+35-:36] ));
		end
		for( genii = 0; genii < 4*FBITS*GENS*HEIGHT; genii+=36 ) begin : _mem_edgelr
			cell_ram36 _ram10 ( .clock( clk ), .data( mem10_din[genii+35-:36] ), .rdaddress( raddr_q[1][0] ), .wraddress( waddr_q ), .wren( we_q ),	.q( mem10_dout[genii+35-:36] ));
			cell_ram36 _ram12 ( .clock( clk ), .data( mem12_din[genii+35-:36] ), .rdaddress( raddr_q[1][2] ), .wraddress( waddr_q ), .wren( we_q ),	.q( mem12_dout[genii+35-:36] ));
		end
		for( genii = 0; genii < 4*FBITS*GENS*WIDTH; genii+=36 ) begin : _mem_edgetb
			cell_ram36 _ram01 ( .clock( clk ), .data( mem01_din[genii+35-:36] ), .rdaddress( raddr_q[0][1] ), .wraddress( waddr_q ), .wren( we_q ),	.q( mem01_dout[genii+35-:36] ));
			cell_ram36 _ram21 ( .clock( clk ), .data( mem21_din[genii+35-:36] ), .rdaddress( raddr_q[2][1] ), .wraddress( waddr_q ), .wren( we_q ),	.q( mem21_dout[genii+35-:36] ));
		end
		for( genii = 0; genii < 4*FBITS*HEIGHT*WIDTH; genii+= 36 ) begin : _mem_core
			cell_ram36 _ram11 ( .clock( clk ), .data( mem11_din[genii+35-:36] ), .rdaddress( raddr_q[1][1] ), .wraddress( waddr_q ), .wren( we_q ),	.q( mem11_dout[genii+35-:36] ));
		end
	endgenerate

	// Video Read port
	logic [2:0] ld_del;  // del = 2*mem+addr_sel_regs = 3
	always_ff @(posedge clk) begin
		// Delay the load (so aligns with read address
		ld_del[2:0] <= { ld_del[1:0], ld }; // delay load
	end
	
	// Dout.q snapshot of the core array (mem11) read data.
	// wired to video display via read mux (note ASYNC path to video). 
	always_ff @(posedge clk) begin
		dout <= ( ld_del[2] ) ? mem11_dout[4*FBITS*HEIGHT*WIDTH-1:0] : dout;
	end

	// Build contiguous EM feild input array (with overlaps) from the nine different memories
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][4*FBITS-1:0] cell_input; 
	always_comb begin
		for( int yy = 0; yy < HEIGHT+2*GENS; yy++ ) begin
			for( int xx = 0; xx < WIDTH+2*GENS; xx++ ) begin
				if      ( xx >= GENS && xx < WIDTH+GENS && yy >= GENS && yy < HEIGHT+GENS ) cell_input[yy][xx] = mem11_dout[((yy-GENS)       *WIDTH+(xx-GENS)      )*4*FBITS+4*FBITS-1-:4*FBITS];//central
				else if ( xx <  GENS                    && yy  < GENS                     ) cell_input[yy][xx] = mem00_dout[( yy             *GENS + xx            )*4*FBITS+4*FBITS-1-:4*FBITS];// UL
				else if ( xx >= GENS && xx < WIDTH+GENS && yy  < GENS                     ) cell_input[yy][xx] = mem01_dout[( yy             *WIDTH+(xx-GENS)      )*4*FBITS+4*FBITS-1-:4*FBITS];// Top
				else if ( xx >= GENS+WIDTH              && yy  < GENS                     ) cell_input[yy][xx] = mem02_dout[( yy             *GENS +(xx-GENS-WIDTH))*4*FBITS+4*FBITS-1-:4*FBITS];// UR
				else if ( xx <  GENS                    && yy >= GENS && yy < GENS+HEIGHT ) cell_input[yy][xx] = mem10_dout[((yy-GENS)       *GENS + xx            )*4*FBITS+4*FBITS-1-:4*FBITS];// LEFT
				else if ( xx >= GENS+WIDTH              && yy >= GENS && yy < GENS+HEIGHT ) cell_input[yy][xx] = mem12_dout[((yy-GENS)       *GENS +(xx-GENS-WIDTH))*4*FBITS+4*FBITS-1-:4*FBITS];// RIGHT
				else if ( xx <  GENS                    && yy >= GENS+HEIGHT              ) cell_input[yy][xx] = mem20_dout[((yy-GENS-HEIGHT)*GENS + xx            )*4*FBITS+4*FBITS-1-:4*FBITS];// LL
				else if ( xx >= GENS && xx < WIDTH+GENS && yy >= GENS+HEIGHT              ) cell_input[yy][xx] = mem21_dout[((yy-GENS-HEIGHT)*WIDTH+(xx-GENS)      )*4*FBITS+4*FBITS-1-:4*FBITS];// Bot
				else/*if( xx >= GENS+WIDTH              && yy >= GENS+HEIGHT            )*/ cell_input[yy][xx] = mem22_dout[((yy-GENS-HEIGHT)*GENS +(xx-GENS-WIDTH))*4*FBITS+4*FBITS-1-:4*FBITS];// LR
			end // xx
		end // yy	
	end 
	
	/////////////////////////////////////////
	//     FTDT 2D Array Calculation
	////////////////////////////////////////
	// 9 Cycle deep pipeline
	// EX, EY Calculations
	// 	Stage 1 : HZ adder
	// 	Stage 2 : Hz differences
	// 	Stage 3 : EX, EY multiplyer inputs
	// 	Stage 4 : EX, EY multiplyer outputs
	// 	Stage 5 : EX, XY accumulates
	// HZX, HZY Calculations
	// 	Stage 6 : EX, EY differences
	// 	Stage 7 : HZx, HZy Multiplier inputs
	// 	Stage 8 : HZx, HZy Multiplier outputs
	// 	Stage 9 : HZx, HZy accumulates

	
	// 	Stage 1 : HZ adder
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][FBITS-1:0]  ex1;
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][FBITS-1:0]  ey1;
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][FBITS-1:0]  hz1;
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][FBITS-1:0] hzx1;
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][FBITS-1:0] hzy1;
	always_ff @(posedge clk) begin
		for( int yy = 0; yy < HEIGHT+2*GENS; yy++ ) begin
			for( int xx = 0; xx < WIDTH+2*GENS; xx++ ) begin
				// Pipe delay
				 ey1[yy][xx] <= cell_input[yy][xx][1*FBITS-1-:FBITS];
				 ex1[yy][xx] <= cell_input[yy][xx][2*FBITS-1-:FBITS];
				hzx1[yy][xx] <= cell_input[yy][xx][3*FBITS-1-:FBITS];
				hzy1[yy][xx] <= cell_input[yy][xx][4*FBITS-1-:FBITS];
				// Stage Calc
				 hz1[yy][xx] <= cell_input[yy][xx][3*FBITS-1-:FBITS] + cell_input[yy][xx][4*FBITS-1-:FBITS]; // nowrap??
			end //xx
		end //yy
	end // always
					

	// 	Stage 2 : Hz differences
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][FBITS-1:0]   ex2;
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][FBITS-1:0]   ey2;
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][FBITS-1:0]  hzx2;
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][FBITS-1:0]  hzy2;
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][FBITS-1:0] dhzx2;
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][FBITS-1:0] dhzy2;

	always_ff @(posedge clk) begin
		for( int yy = 0; yy < HEIGHT+2*GENS; yy++ ) begin
			for( int xx = 0; xx < WIDTH+2*GENS; xx++ ) begin
				// Pipe Delay
				 ey2[yy][xx] <=  ey1[yy][xx];
				 ex2[yy][xx] <=  ex1[yy][xx];
				hzx2[yy][xx] <= hzx1[yy][xx];
				hzy2[yy][xx] <= hzy1[yy][xx];
			end // xx
		end // yy
		// offset from UL corner
		for( int yy = 1; yy < HEIGHT+2*GENS; yy++ ) begin
			for( int xx = 1; xx < WIDTH+2*GENS; xx++ ) begin
				// Stage Calc
				dhzy2[yy][xx] <= hz1[yy][xx] - hz1[yy-1][xx]; // nowrap?	
				dhzx2[yy][xx] <= hz1[yy][xx] - hz1[yy][xx-1];	
			end //xx
		end //yy
	end // always

	// 	Stage 3 : EX, EY multiplyer inputs
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][FBITS-1:0]  hzx3;
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][FBITS-1:0]  hzy3;
	always_ff @(posedge clk) begin
		for( int yy = 0; yy < HEIGHT+2*GENS; yy++ ) begin
			for( int xx = 0; xx < WIDTH+2*GENS; xx++ ) begin
				// Pipe Delay
				hzx3[yy][xx] <= hzx2[yy][xx];
				hzy3[yy][xx] <= hzy2[yy][xx];
			end // xx
		end // yy	
	end // always
	
	//    Stage 3,4 : Generate EY Multiplers with input/output stage3,4 regs built in
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][2*FBITS-1:0]  scale_ey4;
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][2*FBITS-1:0]  scale_dhzx4;
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][2*FBITS-1:0]  scale_ex4;
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][2*FBITS-1:0]  scale_dhzy4;
	genvar genyy, genxx;
	generate
		for( genyy = 0; genyy < HEIGHT+2*GENS; genyy++ ) begin : i_emuly
			for( genxx = 0; genxx < WIDTH+2*GENS; genxx++ ) begin : i_emulx
				smult18 i_emul0 ( .clk( clk ), .dataout(   scale_ey4[genyy][genxx] ), .dataa(   ey2[genyy][genxx] ), .datab( alpha_eyey ) );
				smult18 i_emul1 ( .clk( clk ), .dataout( scale_dhzy4[genyy][genxx] ), .dataa( dhzx2[genyy][genxx] ), .datab( alpha_ey   ) );
				smult18 i_emul2 ( .clk( clk ), .dataout(   scale_ex4[genyy][genxx] ), .dataa(   ex2[genyy][genxx] ), .datab( alpha_exex ) );
				smult18 i_emul3 ( .clk( clk ), .dataout( scale_dhzx4[genyy][genxx] ), .dataa( dhzy2[genyy][genxx] ), .datab( alpha_ex   ) );
			end // xx
		end // yy	
	endgenerate

	// 	Stage 4 : EX, EY multiplyer outputs
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][FBITS-1:0]  hzx4;
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][FBITS-1:0]  hzy4;	
	always_ff @(posedge clk) begin
		for( int yy = 0; yy < HEIGHT+2*GENS; yy++ ) begin
			for( int xx = 0; xx < WIDTH+2*GENS; xx++ ) begin
				// Pipe Delay
				hzx4[yy][xx] <= hzx3[yy][xx];
				hzy4[yy][xx] <= hzy3[yy][xx];
			end // xx
		end // yy	
	end // always

	// 	Stage 5 : EX, XY accumulates
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][FBITS-1:0]  hzx5;
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][FBITS-1:0]  hzy5;	
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][FBITS-1:0]   ex5;
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][FBITS-1:0]   ey5;

	always_ff @(posedge clk) begin
		for( int yy = 0; yy < HEIGHT+2*GENS; yy++ ) begin
			for( int xx = 0; xx < WIDTH+2*GENS; xx++ ) begin
				// Pipe Delay
				hzx5[yy][xx] <= hzx4[yy][xx];
				hzy5[yy][xx] <= hzy4[yy][xx];
				// Stage Calc
				ex5 <=   scale_ey4[yy][xx][FBITS*2-1-:FBITS] + scale_dhzx4[yy][xx][FBITS*2-1-:FBITS]; // nowrap?
				ey5 <=   scale_ex4[yy][xx][FBITS*2-1-:FBITS] + scale_dhzy4[yy][xx][FBITS*2-1-:FBITS]; // nowrap?
			end // xx
		end // yy	
	end // always
	
	// 	Stage 6 : EX, EY differences
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][FBITS-1:0]  hzx6;
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][FBITS-1:0]  hzy6;	
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][FBITS-1:0]   ex6;
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][FBITS-1:0]   ey6;
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][FBITS-1:0] deyx6;
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][FBITS-1:0] dexy6;	
	always_ff @(posedge clk) begin
		for( int yy = 0; yy < HEIGHT+2*GENS; yy++ ) begin
			for( int xx = 0; xx < WIDTH+2*GENS; xx++ ) begin
				// Pipe Delay
				 ey6[yy][xx] <=  ey5[yy][xx];
				 ex6[yy][xx] <=  ex5[yy][xx];
				hzx6[yy][xx] <= hzx5[yy][xx];
				hzy6[yy][xx] <= hzy5[yy][xx];
			end // xx
		end // yy
		// offset into LR corner
		for( int yy = 0; yy < HEIGHT+2*GENS-1; yy++ ) begin
			for( int xx = 0; xx < WIDTH+2*GENS-1; xx++ ) begin
				// Stage Calc
				dexy6[yy][xx] <= ex5[yy+1][xx] - ex5[yy][xx]; // nowrap?	
				deyx6[yy][xx] <= ey5[yy][xx+1] - ey5[yy][xx];	
			end //xx
		end //yy
	end // always

	// 	Stage 7 : HZx, HZy Multiplier inputs
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][FBITS-1:0]   ex7;
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][FBITS-1:0]   ey7;
	always_ff @(posedge clk) begin
		for( int yy = 0; yy < HEIGHT+2*GENS; yy++ ) begin
			for( int xx = 0; xx < WIDTH+2*GENS; xx++ ) begin
				// Pipe Delay
				ex7[yy][xx] <= ex6[yy][xx];
				ey7[yy][xx] <= ey6[yy][xx];
			end // xx
		end // yy	
	end // always

	//    Stage 7,8 : Generate EY Multiplers with input/output stage3,4 regs built in
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][2*FBITS-1:0]  scale_hzy8;
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][2*FBITS-1:0]  scale_deyx8;
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][2*FBITS-1:0]  scale_hzx8;
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][2*FBITS-1:0]  scale_dexy8;
	//genvar genyy, genxx;
	generate
		for( genyy = 0; genyy < HEIGHT+2*GENS; genyy++ ) begin : i_hmuly
			for( genxx = 0; genxx < WIDTH+2*GENS; genxx++ ) begin : i_hmulx
				smult18 i_hmul4 ( .clk( clk ), .dataout(  scale_hzy8[genyy][genxx] ), .dataa(  hzy6[genyy][genxx] ), .datab( alpha_hzyhz ) );
				smult18 i_hmul5 ( .clk( clk ), .dataout( scale_deyx8[genyy][genxx] ), .dataa( deyx6[genyy][genxx] ), .datab( alpha_hzy   ) );
				smult18 i_hmul6 ( .clk( clk ), .dataout(  scale_hzx8[genyy][genxx] ), .dataa(  hzx6[genyy][genxx] ), .datab( alpha_hzxhz ) );
				smult18 i_hmul7 ( .clk( clk ), .dataout( scale_dexy8[genyy][genxx] ), .dataa( dexy6[genyy][genxx] ), .datab( alpha_hzx   ) );
			end // xx
		end // yy	
	endgenerate

	
	// 	Stage 8 : HZx, HZy Multiplier outputs
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][FBITS-1:0]   ex8;
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][FBITS-1:0]   ey8;
	always_ff @(posedge clk) begin
		for( int yy = 0; yy < HEIGHT+2*GENS; yy++ ) begin
			for( int xx = 0; xx < WIDTH+2*GENS; xx++ ) begin
				// Pipe Delay
				ex7[yy][xx] <= ex6[yy][xx];
				ey7[yy][xx] <= ey6[yy][xx];
			end // xx
		end // yy	
	end // always


	// 	Stage 9 : HZx, HZy accumulates	
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][FBITS-1:0]   ex9;
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][FBITS-1:0]   ey9;
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][FBITS-1:0]  hzx9;
	logic [HEIGHT+2*GENS-1:0][WIDTH+2*GENS-1:0][FBITS-1:0]  hzy9;	
	always_ff @(posedge clk) begin
		for( int yy = 0; yy < HEIGHT+2*GENS; yy++ ) begin
			for( int xx = 0; xx < WIDTH+2*GENS; xx++ ) begin
				// Pipe Delay
				ex9[yy][xx] <= ex8[yy][xx];
				ey9[yy][xx] <= ey8[yy][xx];
				// Stage Calc
				hzx9 <=   scale_hzy8[yy][xx][FBITS*2-1-:FBITS] + scale_deyx8[yy][xx][FBITS*2-1-:FBITS]; // nowrap?
				hzy9 <=   scale_hzx8[yy][xx][FBITS*2-1-:FBITS] + scale_dexy8[yy][xx][FBITS*2-1-:FBITS]; // nowrap?
			end // xx
		end // yy	
	end // always
	
	// Connect last reg to ram write data
	logic [HEIGHT-1:0][WIDTH-1:0][4*FBITS-1:0] out; // final registered output generation	 
	always_comb begin 
		for( int xx = 0; xx < WIDTH; xx++ ) 
			for( int yy = 0; yy < HEIGHT; yy++ ) 
				out[yy][xx] <= {  ex9[yy][xx],
				                  ey9[yy][xx],
									  hzx9[yy][xx],
									  hzy9[yy][xx] };
	end

	
	/////////////////////////////////////////
	//     Array Writeback
	////////////////////////////////////////
	
	
	// Init data mux before fanout so init data is written coherently 
	// Data is shifted in serially (big endian), when init_q is set.
	logic [HEIGHT-1:0][WIDTH-1:0][4*FBITS-1:0] write_data;
	logic dummy;
	always_ff @(posedge clk) begin
		{dummy, write_data} <= ( init_q ) ? { write_data, init_data } : { 1'b0, out };
	end
				
	// Format write data for memory inputs with boundary replication and cross wiring
	always_comb begin
		// mem_din central array
		for( int xx = 0; xx < WIDTH; xx++ ) begin
			for( int yy = 0; yy < HEIGHT; yy++ ) begin
				mem11_din[(yy*WIDTH+xx)*4*FBITS+4*FBITS-1-:4*FBITS] = write_data[yy][xx];
			end // yy
		end // gg
		// Top Bot
		for( int xx = 0; xx < WIDTH; xx ++ ) begin
			for( int yy = 0; yy < GENS; yy++ ) begin
				mem01_din[(yy*WIDTH+xx)*4*FBITS+4*FBITS-1-:4*FBITS] = write_data[HEIGHT-GENS+yy][xx]; // Top is taken from botton
				mem21_din[(yy*WIDTH+xx)*4*FBITS+4*FBITS-1-:4*FBITS] = write_data[            yy][xx]; // Bot is taken from top
			end // yy
		end // xx
		// Sides
		for( int xx = 0; xx < GENS; xx++ ) begin
			for( int yy = 0; yy < HEIGHT; yy++ ) begin
				mem10_din[(yy*GENS+xx)*4*FBITS+4*FBITS-1-:4*FBITS]  = write_data[yy][WIDTH-GENS+xx];	// Left is taken from right
				mem12_din[(yy*GENS+xx)*4*FBITS+4*FBITS-1-:4*FBITS]  = write_data[yy][           xx];	// Right is taken from left
			end // yy
		end // xx
		// Corners
		for( int xx = 0; xx < GENS; xx++ ) begin
			for( int yy = 0; yy < GENS; yy++ ) begin
				mem00_din[(yy*GENS+xx)*4*FBITS+4*FBITS-1-:4*FBITS] = write_data[HEIGHT-GENS+yy][WIDTH-GENS+xx]; 	// UL gets LR
				mem02_din[(yy*GENS+xx)*4*FBITS+4*FBITS-1-:4*FBITS] = write_data[HEIGHT-GENS+yy][           xx]; 	// UR gets LL
				mem20_din[(yy*GENS+xx)*4*FBITS+4*FBITS-1-:4*FBITS] = write_data[            yy][WIDTH-GENS+xx]; 	// LL gets UR
				mem22_din[(yy*GENS+xx)*4*FBITS+4*FBITS-1-:4*FBITS] = write_data[            yy][           xx]; 	// LR gets UL
			end // xx
		end // yy
	end

endmodule // ftdt_2d	

// Quartus Prime Verilog Template
// Signed multiply with input and output registers
// May be replaced by generated module
module smult18
#(parameter WIDTH=18)
(
	input clk,
	input signed [WIDTH-1:0] dataa,
	input signed [WIDTH-1:0] datab,
	output reg signed [2*WIDTH-1:0] dataout
);

	// Declare input and output registers
	reg signed [WIDTH-1:0] dataa_reg;
	reg signed [WIDTH-1:0] datab_reg;
	wire signed [2*WIDTH-1:0] mult_out;

	// Store the result of the multiply
	assign mult_out = dataa_reg * datab_reg;

	// Update data
	always @ (posedge clk)
	begin
		dataa_reg <= dataa;
		datab_reg <= datab;
		dataout <= mult_out;
	end

endmodule

