//============================================================================
//  Arcade: Space Firebird
//
//  Mike Coates 
//
//  version 001 initial release - 2026
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

// Enable overlay (or not) for debugging
//`define DEBUG_MODE

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////

assign USER_OUT = '1;

assign AUDIO_S   = 1;
assign AUDIO_MIX = 0;

assign VGA_F1    = 0;
assign VGA_SCALER= 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;
assign FB_FORCE_BLANK = 0;
assign VGA_DISABLE = 0;

assign LED_USER  = ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;

assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

wire [1:0] ar = status[20:19];

assign VIDEO_ARX = (!ar) ? ((status[2])  ? 8'd121 : 8'd91) : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? ((status[2])  ? 8'd91 : 8'd121) : 12'd0;

wire iRST = RESET | ioctl_download | status[0] | buttons[1];

`include "build_id.v" 
localparam CONF_STR = {
	"A.FIREBIRD;;",
   "OOR,CRT H adjust,0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
   "OSV,CRT V adjust,0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
	"H0OJK,Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"H1H0O2,Orientation,Vert,Horz;",
	"O35,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"-;",
	"DIP;",
	"-;",
`ifdef DEBUG_MODE
	"OB,Debug display,Off,On;",
	"-;",
`endif
	"R0,Reset;",
	"J1,Fire 1,Fire 2,Start 1P,Start 2P,Coin;",
	"jn,Start,Select,R;",
	"V,v",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_sys, clk_vid, clk_cpu, clk_mem, clk_snd;
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_vid),			// 20.00 Mhz
	.outclk_1(clk_sys), 			// 32.00 Mhz
	.outclk_2(clk_cpu), 			//  4.00 Mhz
	.outclk_3(clk_mem),			// 80.00 Mhz
	.outclk_4(clk_snd),			//  6.00 Mhz
	.locked(pll_locked)
);

///////////////////////////////////////////////////

wire [31:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire        direct_video;
wire [15:0] joy1, joy2;

wire        ioctl_download;
wire  [7:0] ioctl_index;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;

wire [21:0] gamma_bus;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.buttons(buttons),
	.status(status),
	.status_menumask({1'd0,direct_video}),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),
	.video_rotated(video_rotated),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_index(ioctl_index),

	.joystick_0(joy1),
	.joystick_1(joy2)
);

localparam mod_firebird = 0;
localparam mod_demon    = 1;

reg [7:0] mod = 0;
always @(posedge clk_sys) if (ioctl_wr & (ioctl_index==1)) mod <= ioctl_dout;

// Dip switches from MRA file
reg [7:0] sw[8];
always @(posedge clk_sys) if (ioctl_wr && (ioctl_index==254) && !ioctl_addr[24:3]) sw[ioctl_addr[2:0]] <= ioctl_dout;


// Combined buttons
wire B1_S = joy1[6];
wire B2_S = joy1[7];
wire B1_C = joy1[8];

wire B1_B = joy1[5];
wire B1_A = joy1[4];
wire B1_U = joy1[3];
wire B1_D = joy1[2];
wire B1_L = joy1[1];
wire B1_R = joy1[0];

wire B2_B = joy2[5];
wire B2_A = joy2[4];
wire B2_U = joy2[3];
wire B2_D = joy2[2];
wire B2_L = joy2[1];
wire B2_R = joy2[0];

// Autocoin option 

wire m_start1;
wire m_start2;
wire m_coin1;

autocoin #(
	.count(64000),
	.delay(2))
autocoin (
  .i_clk(clk_cpu),
  .i_coin(B1_C),
  .i_start1(B1_S),
  .i_start2(B2_S),
  .o_coin(m_coin1),
  .o_start1(m_start1),
  .o_start2(m_start2),
  .enable(sw[1][0])
);

wire hblank, vblank;
wire hs, vs;
wire [8:0] HCount;
wire [8:0] VCount;
wire [7:0] r,g,b;

wire [ 3:0] hoffset, voffset;
assign { voffset, hoffset } = status[31:24];

wire no_rotate = status[2] | direct_video;
wire rotate_ccw = 1;
wire flip = 0;
wire video_rotated;

wire pix_ena;
wire [1:0] pix_cnt;

video_timing VIDEO_TIMING
(
	.RESET(iRST),
	.clk(clk_vid),
	.HOFFSET(hoffset),
	.VOFFSET(voffset),
	.pix_clk(pix_ena),
	.pixcount(pix_cnt),
	.hcnt(HCount),
	.vcnt(VCount),
	.hsync(hs),
	.vsync(vs),
	.hblank(hblank),
	.vblank(vblank)
);

screen_rotate screen_rotate (.*);

arcade_video #(512,24) arcade_video
(
	.*,

	.clk_video(clk_vid),
	.ce_pix(pix_ena),

`ifdef DEBUG_MODE
	.RGB_in(rgb_ovo),
`else
	.RGB_in({r,g,b}),
`endif
	.HBlank(hblank),
	.VBlank(vblank),
	.HSync(hs),
	.VSync(vs),

	.fx(status[5:3])
);

wire [15:0] audio;

SPACEFIREBIRD bird 
(
	.I_Firebird(mod == mod_firebird),
	.I_Bullet(sw[1][1]),
	.I_Song(mod == mod_firebird ? 1'b0 : sw[1][2]),

	.O_VIDEO_R(r),
	.O_VIDEO_G(g),
	.O_VIDEO_B(b),
	
	.I_HCOUNT(HCount),
	.I_VCOUNT(VCount),

	.dn_addr(ioctl_addr[15:0]),
	.dn_data(ioctl_dout),
	.dn_wr(ioctl_wr && !ioctl_index),
	.dn_ld(ioctl_download),

	.SAMPLE_CTL(sample_ctrl),
	.O_AUDIO(audio),

	.in0({B1_A,1'b0,1'b0,B1_B,1'b0,1'b0,B1_L,B1_R}),
	.in1({B2_A,1'b0,1'b0,B2_B,1'b0,1'b0,B2_L,B2_R}),
	.in2({~m_coin1,1'b0,1'b0,1'b0,m_start2,m_start1,1'd0,1'd0}),
	.dipsw1(sw[1][0] ? {2'd0,sw[0][5:4],2'd0,sw[0][1:0]} : {2'd0,sw[0][5:0]}),

// debug display fields
`ifdef DEBUG_MODE	
	.PCADDR(PC),
	.PCDATA(DT),
	.O_FLIP(sflip),
`endif	

	.RESET(iRST),
	.I_PIX(pix_cnt),
	
	.CPU_CLK(clk_cpu),
	.VID_CLK(clk_vid),
	.SND_CLK(clk_snd),
	.SYS_CLK(clk_sys)
);

////////////////////////////  Samples   ///////////////////////////////////

reg  [27:0] wav_addr;
wire [15:0] wav_data_o;
wire        wav_want_byte;
wire [3:0]  sample_ctrl;

reg  Ready_L;
wire Ready;
reg  [15:0] wav_data;


sdram sdram
(
		 .*,
		 .init(~pll_locked),
		 .clk(clk_mem),

		 .addr(ioctl_download ? ioctl_addr : {wav_addr[24:1],1'd0}),
		 .we(ioctl_download && ioctl_wr && (ioctl_index == 6)),
		 .rd(~ioctl_download & wav_want_byte),
		 .din(ioctl_dout),
		 .dout(wav_data_o),

		 .ready(Ready)
);


always @(posedge clk_mem)
begin
         Ready_L <= Ready;
         // on Ready set keep data
         if(Ready && ~Ready_L) wav_data <= wav_data_o;
end

// Link to Samples module

samples samples
(
	.audio_enabled(1'd1),
	.audio_port_0({4'd0,sample_ctrl}),	
	.audio_port_1(8'd0),

	.wave_addr(wav_addr),        
	.wave_read(wav_want_byte),   
	.wave_data({wav_data,wav_data}),

	.samples_ok(),

	.dl_addr(ioctl_addr),
	.dl_wr(ioctl_wr),
	.dl_data(ioctl_dout),
	.dl_download(ioctl_download && (ioctl_index == 5)),
	
	.CLK_SYS(clk_sys),
	.clock(clk_mem),
	.reset(iRST),
	
	.audio_in(audio),
	.audio_out_L(AUDIO_L),
	.audio_out_R(AUDIO_R)
);


//--
//-- Debug
//--

`ifdef DEBUG_MODE

// For putting characters in at position POS
`define LC(POS, VAL) Line1[POS*5+4:POS*5] <= VAL;

// for putting nibbles in at position POS
`define L4(POS, VAL) Line1[POS*5+3:POS*5] <= VAL;

// for putting 8 bit numbers in at position POS and POS+1
`define L8(POS, VAL) Line1[POS*5+3:POS*5] <= VAL[7:4]; Line1[POS*5+8:POS*5+5] <= VAL[3:0];

// for putting 16 bit numbers in at position POS to POS+3
`define L16(POS, VAL) Line1[POS*5+3:POS*5] <= VAL[15:12]; Line1[POS*5+8:POS*5+5] <= VAL[11:8]; Line1[POS*5+13:POS*5+10] <= VAL[7:4]; Line1[POS*5+18:POS*5+15] <= VAL[3:0];

reg [23:0] rgb_ovo;
reg [149:0] Line1,Line2;

ovo OVERLAY
(
    .i_r(r),
    .i_g(g),
    .i_b(b),
    .i_clk(clk_vid),
	 .i_pix(pix_ena),
	 
	 .i_Hcount(HCount),
	 .i_VCount(VCount),

    .o_r(rgb_ovo[23:16]),
    .o_g(rgb_ovo[15:8]),
    .o_b(rgb_ovo[7:0]),
    .ena(status[11]),

    .in0(Line1),
    .in1(Line2)
);

wire [15:0] PC;
wire [7:0] DT;
wire sflip;

always @(posedge clk_sys)
begin
	`LC(0,5'b10000)
	`L16(1,PC)
	`LC(5,5'b10000)
	`L8(6,DT)
	`LC(8,5'b10000)
	`L4(9,{3'b000,sflip})
	`LC(10,5'b10000)	
end	

`endif

		 
endmodule

