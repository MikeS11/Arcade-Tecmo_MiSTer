//   __   __     __  __     __         __
//  /\ "-.\ \   /\ \/\ \   /\ \       /\ \
//  \ \ \-.  \  \ \ \_\ \  \ \ \____  \ \ \____
//   \ \_\\"\_\  \ \_____\  \ \_____\  \ \_____\
//    \/_/ \/_/   \/_____/   \/_____/   \/_____/
//   ______     ______       __     ______     ______     ______
//  /\  __ \   /\  == \     /\ \   /\  ___\   /\  ___\   /\__  _\
//  \ \ \/\ \  \ \  __<    _\_\ \  \ \  __\   \ \ \____  \/_/\ \/
//   \ \_____\  \ \_____\ /\_____\  \ \_____\  \ \_____\    \ \_\
//    \/_____/   \/_____/ \/_____/   \/_____/   \/_____/     \/_/
//
// https://joshbassett.info
// https://twitter.com/nullobject
// https://github.com/nullobject
//
// Copyright (c) 2020 Josh Bassett
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

module emu
(
  //Master input clock
  input         CLK_50M,

  //Async reset from top-level module.
  //Can be used as initial reset.
  input         RESET,

  //Must be passed to hps_io module
  inout  [45:0] HPS_BUS,

  //Base video clock. Usually equals to CLK_SYS.
  output        VGA_CLK,

  //Multiple resolutions are supported using different VGA_CE rates.
  //Must be based on CLK_VIDEO
  output        VGA_CE,

  output  [7:0] VGA_R,
  output  [7:0] VGA_G,
  output  [7:0] VGA_B,
  output        VGA_HS,
  output        VGA_VS,
  output        VGA_DE,    // = ~(VBlank | HBlank)
  output        VGA_F1,

  //Base video clock. Usually equals to CLK_SYS.
  output        HDMI_CLK,

  //Multiple resolutions are supported using different HDMI_CE rates.
  //Must be based on CLK_VIDEO
  output        HDMI_CE,

  output  [7:0] HDMI_R,
  output  [7:0] HDMI_G,
  output  [7:0] HDMI_B,
  output        HDMI_HS,
  output        HDMI_VS,
  output        HDMI_DE,   // = ~(VBlank | HBlank)
  output  [1:0] HDMI_SL,   // scanlines fx

  //Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
  output  [7:0] HDMI_ARX,
  output  [7:0] HDMI_ARY,

  output        LED_USER,  // 1 - ON, 0 - OFF.

  // b[1]: 0 - LED status is system status OR'd with b[0]
  //       1 - LED status is controled solely by b[0]
  // hint: supply 2'b00 to let the system control the LED.
  output  [1:0] LED_POWER,
  output  [1:0] LED_DISK,

  output [15:0] AUDIO_L,
  output [15:0] AUDIO_R,
  output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned

  //SDRAM interface with lower latency
  output        SDRAM_CLK,
  output        SDRAM_CKE,
  output [12:0] SDRAM_A,
  output  [1:0] SDRAM_BA,
  inout  [15:0] SDRAM_DQ,
  output        SDRAM_DQML,
  output        SDRAM_DQMH,
  output        SDRAM_nCS,
  output        SDRAM_nCAS,
  output        SDRAM_nRAS,
  output        SDRAM_nWE,

  // Open-drain User port.
  // 0 - D+/RX
  // 1 - D-/TX
  // 2..6 - USR2..USR6
  // Set USER_OUT to 1 to read from USER_IN.
  input   [6:0] USER_IN,
  output  [6:0] USER_OUT
);

assign VGA_F1 = 0;

assign AUDIO_S = 1;
assign AUDIO_R = AUDIO_L;

assign LED_DISK  = 0;
assign LED_POWER = 0;

assign HDMI_ARX = status[1] ? 8'd16 : status[2] ? 8'd3 : 8'd4;
assign HDMI_ARY = status[1] ? 8'd9  : status[2] ? 8'd4 : 8'd3;

assign SDRAM_CLK = clk_sdram;

`include "build_id.v"
localparam CONF_STR = {
  "A.Tecmo;;",
  "O1,Aspect Ratio,Original,Wide;",
  "O2,Orientation,Horz,Vert;",
  "O3,Flip Screen,Off,On;",
  "O46,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
  "O7,Debug,Off,On;",
  "-;",
  "DIP;",
  "-;",
  "R0,Reset;",
  "J1,B0,B1,B2,Start,Coin,Pause;",
  "V,v",`BUILD_DATE
};

////////////////////////////////////////////////////////////////////////////////
// CLOCKS
////////////////////////////////////////////////////////////////////////////////

wire clk_sys, clk_sdram;
wire locked;

pll pll
(
  .refclk(CLK_50M),
  .outclk_0(clk_sys),
  .outclk_1(clk_sdram),
  .locked(locked)
);

////////////////////////////////////////////////////////////////////////////////
// HPS IO
////////////////////////////////////////////////////////////////////////////////

wire  [1:0] buttons;
wire [31:0] status;
wire        forced_scandoubler;
wire [21:0] gamma_bus;
wire        direct_video;

wire [24:0] ioctl_addr;
wire  [7:0] ioctl_data;
wire        ioctl_wr;
wire        ioctl_download;
wire  [7:0] ioctl_index;

wire [10:0] ps2_key;

wire  [9:0] joystick_0, joystick_1;

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
  .clk_sys(clk_sys),
  .HPS_BUS(HPS_BUS),

  .conf_str(CONF_STR),

  .buttons(buttons),
  .status(status),
  .status_menumask(direct_video),
  .forced_scandoubler(forced_scandoubler),
  .gamma_bus(gamma_bus),
  .direct_video(direct_video),

  .ioctl_addr(ioctl_addr),
  .ioctl_dout(ioctl_data),
  .ioctl_wr(ioctl_wr),
  .ioctl_download(ioctl_download),
  .ioctl_index(ioctl_index),

  .joystick_0(joystick_0),
  .joystick_1(joystick_1),

  .ps2_key(ps2_key)
);

////////////////////////////////////////////////////////////////////////////////
// VIDEO
////////////////////////////////////////////////////////////////////////////////

wire       ce_pix;
wire [3:0] r, g, b;
wire       hsync, vsync;
wire       hblank, vblank;
wire       no_rotate = ~status[2] & ~direct_video;

arcade_video #(256, 224, 12) arcade_video
(
  .*,

  // clock
  .clk_video(clk_sys),
  .ce_pix(ce_pix),

  // video
  .RGB_in({r, g, b}),
  .HBlank(hblank),
  .VBlank(vblank),
  .HSync(hsync),
  .VSync(vsync),

  // rotate/aspect
  .no_rotate(no_rotate),
  .rotate_ccw(0),
  .fx(status[6:4])
);

////////////////////////////////////////////////////////////////////////////////
// SDRAM
////////////////////////////////////////////////////////////////////////////////

wire [22:0] sdram_addr;
wire [31:0] sdram_data;
wire        sdram_we;
wire        sdram_req;
wire        sdram_ack;
wire        sdram_valid;
wire [31:0] sdram_q;

sdram #(.CLK_FREQ(96.0)) sdram
(
  .reset(~locked),
  .clk(clk_sys),

  // controller interface
  .addr(sdram_addr),
  .data(sdram_data),
  .we(sdram_we),
  .req(sdram_req),
  .ack(sdram_ack),
  .valid(sdram_valid),
  .q(sdram_q),

  // SDRAM interface
  .sdram_a(SDRAM_A),
  .sdram_ba(SDRAM_BA),
  .sdram_dq(SDRAM_DQ),
  .sdram_cke(SDRAM_CKE),
  .sdram_cs_n(SDRAM_nCS),
  .sdram_ras_n(SDRAM_nRAS),
  .sdram_cas_n(SDRAM_nCAS),
  .sdram_we_n(SDRAM_nWE),
  .sdram_dqml(SDRAM_DQML),
  .sdram_dqmh(SDRAM_DQMH)
);

////////////////////////////////////////////////////////////////////////////////
// CONTROLS
////////////////////////////////////////////////////////////////////////////////

wire       pressed = ps2_key[9];
wire [7:0] code    = ps2_key[7:0];

reg key_left  = 0;
reg key_right = 0;
reg key_down  = 0;
reg key_up    = 0;
reg key_ctrl  = 0;
reg key_alt   = 0;
reg key_space = 0;
reg key_1     = 0;
reg key_2     = 0;
reg key_5     = 0;
reg key_6     = 0;
reg key_a     = 0;
reg key_s     = 0;
reg key_q     = 0;
reg key_r     = 0;
reg key_f     = 0;
reg key_d     = 0;
reg key_g     = 0;
reg key_p     = 0;

always @(posedge clk_sys) begin
  reg old_state;
  old_state <= ps2_key[10];

  if (old_state != ps2_key[10]) begin
    case (code)
      'h75: key_up    <= pressed;
      'h72: key_down  <= pressed;
      'h6B: key_left  <= pressed;
      'h74: key_right <= pressed;
      'h14: key_ctrl  <= pressed;
      'h11: key_alt   <= pressed;
      'h29: key_space <= pressed;
      'h16: key_1     <= pressed;
      'h1E: key_2     <= pressed;
      'h2E: key_5     <= pressed;
      'h36: key_6     <= pressed;
      'h1C: key_a     <= pressed;
      'h1B: key_s     <= pressed;
      'h15: key_q     <= pressed;
      'h2D: key_r     <= pressed;
      'h2B: key_f     <= pressed;
      'h23: key_d     <= pressed;
      'h34: key_g     <= pressed;
      'h4d: key_p     <= pressed;
    endcase
  end
end

wire player_1_up       = key_up    | joystick_0[3];
wire player_1_down     = key_down  | joystick_0[2];
wire player_1_left     = key_left  | joystick_0[1];
wire player_1_right    = key_right | joystick_0[0];
wire player_1_button_1 = key_ctrl  | joystick_0[4];
wire player_1_button_2 = key_alt   | joystick_0[5];
wire player_1_button_3 = key_space | joystick_0[6];
wire player_1_start    = key_1     | joystick_0[7];
wire player_1_coin     = key_5     | joystick_0[8];
wire player_1_pause    = key_p     | joystick_0[9];
wire player_2_up       = key_r     | joystick_1[3];
wire player_2_down     = key_f     | joystick_1[2];
wire player_2_left     = key_d     | joystick_1[1];
wire player_2_right    = key_g     | joystick_1[0];
wire player_2_button_1 = key_a     | joystick_1[4];
wire player_2_button_2 = key_s     | joystick_1[5];
wire player_2_button_3 = key_q     | joystick_1[6];
wire player_2_start    = key_2     | joystick_1[7];
wire player_2_coin     = key_6     | joystick_1[8];
wire player_2_pause    =             joystick_0[9];

////////////////////////////////////////////////////////////////////////////////
// GAME
////////////////////////////////////////////////////////////////////////////////

wire reset = RESET | status[0] | buttons[1] | ~locked;
reg [7:0] sw[8];
reg [3:0] game_index = 0;

always @(posedge clk_sys) begin
  // set game index
  if (ioctl_wr && (ioctl_index == 1)) game_index <= ioctl_data[3:0];

  // set DIP switches
  if (ioctl_wr && (ioctl_index == 254) && !ioctl_addr[24:3]) sw[ioctl_addr[2:0]] <= ioctl_data;
end

tecmo #(.CLK_FREQ(96.0)) tecmo
(
  .reset(reset),

  .clk(clk_sys),
  .cen_6(ce_pix),

  .debug(status[7]),
  .flip(status[3]),

  .joy_1({player_1_up, player_1_down, player_1_right, player_1_left}),
  .joy_2({player_2_up, player_2_down, player_2_right, player_2_left}),
  .buttons_1({2'b0, player_1_button_3, player_1_button_2, player_1_button_1}),
  .buttons_2({2'b0, player_2_button_3, player_2_button_2, player_2_button_1}),
  .sys({player_1_coin, player_2_coin, player_1_start, player_2_start}),
  .pause(player_1_pause | player_2_pause),

  .dip_1(sw[0]),
  .dip_2(sw[1]),

  .sdram_addr(sdram_addr),
  .sdram_data(sdram_data),
  .sdram_we(sdram_we),
  .sdram_req(sdram_req),
  .sdram_ack(sdram_ack),
  .sdram_valid(sdram_valid),
  .sdram_q(sdram_q),

  .ioctl_addr(ioctl_addr[19:0]),
  .ioctl_data(ioctl_data),
  .ioctl_wr(ioctl_wr && !ioctl_index),
  .ioctl_download(ioctl_download && !ioctl_index),

  .game_index(game_index),

  .hsync(hsync),
  .vsync(vsync),
  .hblank(hblank),
  .vblank(vblank),

  .r(r),
  .g(g),
  .b(b),

  .audio(AUDIO_L)
);

endmodule
