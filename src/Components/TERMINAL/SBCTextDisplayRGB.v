// This file is copyright by Grant Searle 2014
// You are free to use this file in your own projects but must never charge for it nor use it without
// acknowledgement.
// Please ask permission from Grant Searle before republishing elsewhere.
// If you use this file or any part of it, please add an acknowledgement to myself and
// a link back to my main web site http://searle.hostei.com/grant/
// and to the "multicomp" page at http://searle.hostei.com/grant/Multicomp/index.html
//
// Please check on the above web pages to see if there are any updates before using this file.
// If for some reason the page is no longer available, please search for "Grant Searle"
// on the internet to see if I have moved to another web hosting service.
//
// Grant Searle
// eMail address available on my main web page link above.
// no timescale needed

// Notes:
//
// Hitchhiker uses the following codes, some of which seem to be GEMDOS extensions to VT52
// http://toshyp.atari.org/en/VT_52_terminal.html
// <ESC>x         - undocumented
// <ESC>E         - clear screen
// <ESC>Y<37><20> - set cursor position
//                - print lots of stuff
// <ESC>j         - save cursor
// <ESC>Y<20><20> - set cursor position
// <ESC>p         - reverse video
//                - print footer line
// <ESC>k         - restore cursor
// <ESC>q         - normal video

module SBCTextDisplayRGB
  (
   input            n_reset,
   input            clk,
   input            n_wr,
   input            n_rd,
   input            regSel,
   input [7:0]      dataIn,
   output reg [7:0] dataOut,
   output           n_int,
   output           n_rts,
   // RGB video signals
   output reg       videoR0,
   output reg       videoR1,
   output reg       videoG0,
   output reg       videoG1,
   output reg       videoB0,
   output reg       videoB1,
   output reg       hSync,
   output reg       vSync,
   // Monochrome video signals
   output reg       video,
   output           sync,
   // Keyboard signals
   inout            ps2Clk,
   inout            ps2Data,
   // FN keys passed out as general signals (momentary and toggled versions)
   output [12:0]    FNkeys,
   output [12:0]    FNtoggledKeys
   );

   parameter [31:0] EXTENDED_CHARSET=1;
   parameter [31:0] COLOUR_ATTS_ENABLED=1;
   parameter [31:0] VERT_CHARS=25;
   parameter [31:0] HORIZ_CHARS=80;
   parameter [31:0] CLOCKS_PER_SCANLINE=1600;
   parameter [31:0] DISPLAY_TOP_SCANLINE=35 + 40;
   parameter [31:0] DISPLAY_LEFT_CLOCK=288;
   parameter [31:0] VERT_SCANLINES=525;
   parameter [31:0] VSYNC_SCANLINES=2;
   parameter [31:0] HSYNC_CLOCKS=192;
   parameter [31:0] VERT_PIXEL_SCANLINES=2;
   parameter [31:0] CLOCKS_PER_PIXEL=2;
   parameter H_SYNC_ACTIVE=1'b0;
   parameter V_SYNC_ACTIVE=1'b0;
   parameter [7:0] DEFAULT_ATT=8'b00001111;
   parameter [7:0] ANSI_DEFAULT_ATT=8'b00000111;
   // background iBGR | foreground iBGR (i=intensity)

   //VGA 640x400
   //constant VERT_CHARS : integer := 25;
   //constant HORIZ_CHARS : integer := 80;
   //constant CLOCKS_PER_SCANLINE : integer := 1600;
   //constant DISPLAY_TOP_SCANLINE : integer := 35;
   //constant DISPLAY_LEFT_CLOCK : integer := 288;
   //constant VERT_SCANLINES : integer := 448;
   //constant VSYNC_SCANLINES : integer := 2;
   //constant HSYNC_CLOCKS : integer := 192;
   //constant VERT_PIXEL_SCANLINES : integer := 2;
   //constant CLOCKS_PER_PIXEL : integer := 2; -- min = 2
   //constant H_SYNC_ACTIVE : std_logic := '0';
   //constant V_SYNC_ACTIVE : std_logic := '1';

   parameter HORIZ_CHAR_MAX = HORIZ_CHARS-1;
   parameter VERT_CHAR_MAX = VERT_CHARS-1;
   parameter CHARS_PER_SCREEN = HORIZ_CHARS*VERT_CHARS;

   reg [12:0]       FNkeysSig = 0;
   reg [12:0]       FNtoggledKeysSig = 0;

   reg              func_reset = 1'b0;
   reg              vActive  = 1'b0;
   reg              hActive  = 1'b0;

   reg [3:0]        pixelClockCount = 0;
   reg [2:0]        pixelCount = 0;

   reg [11:0]       horizCount = 0;
   reg [9:0]        vertLineCount = 0;

   reg [4:0]        charVert = 0;
   reg [3:0]        charScanLine = 0;

   reg [6:0]        charHoriz;
   reg [3:0]        charBit;

   reg [4:0]        cursorVert = 0;
   reg [6:0]        cursorHoriz = 0;

   reg [4:0]        cursorVertRestore = 0;
   reg [6:0]        cursorHorizRestore = 0;

   reg [4:0]        savedCursorVert = 0;
   reg [6:0]        savedCursorHoriz =0;

   reg [10:0]       startAddr = 0;
   reg [10:0]       cursAddr;

   reg [10:0]       dispAddr;
   wire [10:0]      charAddr;

   wire [7:0]       dispCharData;
   reg [7:0]        dispCharWRData;
   wire [7:0]       dispCharRDData;

   wire [7:0]       dispAttData;
   reg [7:0]        dispAttWRData = DEFAULT_ATT; // iBGR(back) iBGR(text)
   wire [7:0]       dispAttRDData;

   wire [7:0]       charData;

   reg              cursorOn  = 1'b1;
   reg              dispWR = 1'b0;
   reg [25:0]       cursBlinkCount;
   reg [25:0]       kbWatchdogTimer = 0;
   reg [25:0]       kbWriteTimer = 0;

   wire             n_int_internal;

   wire [7:0]       statusReg;
   reg [7:0]        controlReg = 8'h00;

   reg [6:0]        kbBuffer[0 : 7];

   reg [3:0]        kbInPointer = 0;
   reg [3:0]        kbReadPointer = 0;
   wire [3:0]       kbBuffCount;
   reg              dispByteWritten = 1'b0;
   reg              dispByteSent = 1'b0;

   reg [7:0]        dispByteLatch;

   parameter
     idle        = 0,
     dispWrite   = 1,
     dispNextLoc = 2,
     clearLine   = 3,
     clearL2     = 4,
     clearScreen = 5,
     clearS2     = 6,
     clearChar   = 7,
     clearC2     = 8,
     insertLine  = 9,
     ins2        = 10,
     ins3        = 11,
     deleteLine  = 12,
     del2        = 13,
     del3        = 14;

   reg [3:0]        dispState = idle;

   parameter
     none                       = 0,
     waitForLeftBracket         = 1,
     processingParams           = 2,
     processingAdditionalParams = 3;

   reg [1:0]        escState = none;

   reg [6:0]        param1 = 0;
   reg [6:0]        param2 = 0;
   reg [6:0]        param3 = 0;
   reg [6:0]        param4 = 0;
   reg [2:0]        paramCount = 0;

   reg              attInverse = 1'b0;
   reg              attBold = DEFAULT_ATT[3];

   reg [7:0]        ps2Byte;
   reg [7:0]        ps2PreviousByte;
   reg [6:0]        ps2ConvertedByte;
   reg [3:0]        ps2ClkCount = 0;
   reg [4:0]        ps2WriteClkCount = 0;
   reg [7:0]        ps2WriteByte = 8'hff;
   reg [7:0]        ps2WriteByte2 = 8'hff;
   reg              ps2PrevClk = 1'b1;
   reg [5:0]        ps2ClkFilter = 0;
   reg              ps2ClkFiltered = 1'b1;

   reg              ps2Shift = 1'b0;
   reg              ps2Ctrl = 1'b0;
   reg              ps2Caps = 1'b1;
   reg              ps2Num = 1'b0;
   reg              ps2Scroll = 1'b0;

   reg              ps2DataOut = 1'b1;
   reg              ps2ClkOut = 1'b1;
   wire             ps2DataIn;
   wire             ps2ClkIn;

   reg              n_kbWR = 1'b1;
   reg              kbWRParity = 1'b0;

   // "globally static" versions of signals for use within generate
   // statements below. Without these intermediate signals the simulator
   // reports an error (even though the design synthesises OK)
   wire [10:0]      cursAddr_xx;
   wire [10:0]      dispAddr_xx;

   // the ASCII codes are expressed in HEX and therefore are 8-bit.
   // However, the MSB is always 0 so we don't want to store the MSB. This
   // function allows us to express the codes here as pairs of hex digits,
   // for readability, but truncates the value to return 7 bits for the
   // hardware implementation.

   function [6:0] t;
      input [7:0]   val;
      begin
         t = val[6:0];
      end
   endfunction


   // scan-code-to-ASCII for UK KEYBOARD MAPPING (except for shift-3 = "#")
   // Read it like this: row 4,col 9 represents scan code 0x49. From a map
   // of the PS/2 keyboard scan codes this is the ". >" key so the unshifted
   // table as has 0x2E (ASCII .) and the shifted table has 0x3E (ASCII >)
   // Do not need a lookup for CTRL because this is simply the ASCII code
   // with bits 6,5 cleared.
   // A value of 0 represents either an unused keycode or a keycode like
   // SHIFT that is processed separately (not looked up in the table).
   // The FN keys do not generate ASCII values to the virtual UART here.
   // Rather, they are used to generate direct output signals. The key
   // codes in the table for the function keys are the values 0x11-0x1C
   // which cannot be generated directly by any keypress and so do not
   // conflict with normal operation.
   // constant kbUnshifted : kbDataArray :=
   // (
   // --  0        1        2        3        4        5        6        7        8        9        A        B        C        D        E        F
   // --       F9                F5       F3       F1       F2       F12               F10      F8       F6       F4       TAB      `
   // t(x"00"),t(x"19"),t(x"00"),t(x"15"),t(x"13"),t(x"11"),t(x"12"),t(x"1C"),t(x"00"),t(x"1A"),t(x"18"),t(x"16"),t(x"14"),t(x"09"),t(x"60"),t(x"00"), -- 0
   // --       l-ALT    l-SHIFT           l-CTRL   q        1                                   z        s        a        w        2
   // t(x"00"),t(x"00"),t(x"00"),t(x"00"),t(x"00"),t(x"71"),t(x"31"),t(x"00"),t(x"00"),t(x"00"),t(x"7A"),t(x"73"),t(x"61"),t(x"77"),t(x"32"),t(x"00"), -- 1
   // --       c        x        d        e        4        3                          SPACE    v        f        t        r        5
   // t(x"00"),t(x"63"),t(x"78"),t(x"64"),t(x"65"),t(x"34"),t(x"33"),t(x"00"),t(x"00"),t(x"20"),t(x"76"),t(x"66"),t(x"74"),t(x"72"),t(x"35"),t(x"00"), -- 2
   // --       n        b        h        g        y        6                                   m        j        u        7        8
   // t(x"00"),t(x"6E"),t(x"62"),t(x"68"),t(x"67"),t(x"79"),t(x"36"),t(x"00"),t(x"00"),t(x"00"),t(x"6D"),t(x"6A"),t(x"75"),t(x"37"),t(x"38"),t(x"00"), -- 3
   // --       ,        k        i        o        0        9                          .        /        l        ;        p        -
   // t(x"00"),t(x"2C"),t(x"6B"),t(x"69"),t(x"6F"),t(x"30"),t(x"39"),t(x"00"),t(x"00"),t(x"2E"),t(x"2F"),t(x"6C"),t(x"3B"),t(x"70"),t(x"2D"),t(x"00"), -- 4
   // --                '                 [        =                          CAPLOCK  r-SHIFT  ENTER    ]                 #~
   // t(x"00"),t(x"00"),t(x"27"),t(x"00"),t(x"5B"),t(x"3D"),t(x"00"),t(x"00"),t(x"00"),t(x"00"),t(x"0D"),t(x"5D"),t(x"00"),t(x"23"),t(x"00"),t(x"00"), -- 5
   // --       \|                                           BACKSP                     KP1               KP4      KP7
   // t(x"00"),t(x"5C"),t(x"00"),t(x"00"),t(x"00"),t(x"00"),t(x"08"),t(x"00"),t(x"00"),t(x"31"),t(x"00"),t(x"34"),t(x"37"),t(x"00"),t(x"00"),t(x"00"), -- 6
   // -- KP0   KP.      KP2      KP5      KP6      KP8      ESC      NUMLCK   F11      KP+      KP3      KP-      KP*      KP9      SCRLCK
   // t(x"30"),t(x"2E"),t(x"32"),t(x"35"),t(x"36"),t(x"38"),t(x"1B"),t(x"00"),t(x"1B"),t(x"2B"),t(x"33"),t(x"2D"),t(x"2A"),t(x"39"),t(x"00"),t(x"00"), -- 7
   // --                         F7
   // t(x"00"),t(x"00"),t(x"00"),t(x"17") -- 8
   // );
   // constant kbShifted : kbDataArray :=
   // (
   // --  0        1        2        3        4        5        6        7        8        9        A        B        C        D        E        F
   // t(x"00"),t(x"19"),t(x"00"),t(x"15"),t(x"13"),t(x"11"),t(x"12"),t(x"1C"),t(x"00"),t(x"1A"),t(x"18"),t(x"16"),t(x"14"),t(x"09"),t(x"00"),t(x"00"), -- 0
   // t(x"00"),t(x"00"),t(x"00"),t(x"00"),t(x"00"),t(x"51"),t(x"21"),t(x"00"),t(x"00"),t(x"00"),t(x"5A"),t(x"53"),t(x"41"),t(x"57"),t(x"22"),t(x"00"), -- 1
   // t(x"00"),t(x"43"),t(x"58"),t(x"44"),t(x"45"),t(x"24"),t(x"23"),t(x"00"),t(x"00"),t(x"20"),t(x"56"),t(x"46"),t(x"54"),t(x"52"),t(x"25"),t(x"00"), -- 2
   // t(x"00"),t(x"4E"),t(x"42"),t(x"48"),t(x"47"),t(x"59"),t(x"5E"),t(x"00"),t(x"00"),t(x"00"),t(x"4D"),t(x"4A"),t(x"55"),t(x"26"),t(x"2A"),t(x"00"), -- 3
   // t(x"00"),t(x"3C"),t(x"4B"),t(x"49"),t(x"4F"),t(x"29"),t(x"28"),t(x"00"),t(x"00"),t(x"3E"),t(x"3F"),t(x"4C"),t(x"3A"),t(x"50"),t(x"5F"),t(x"00"), -- 4
   // t(x"00"),t(x"00"),t(x"40"),t(x"00"),t(x"7B"),t(x"2B"),t(x"00"),t(x"00"),t(x"00"),t(x"00"),t(x"0D"),t(x"7D"),t(x"00"),t(x"7E"),t(x"00"),t(x"00"), -- 5
   // t(x"00"),t(x"7C"),t(x"00"),t(x"00"),t(x"00"),t(x"00"),t(x"08"),t(x"00"),t(x"00"),t(x"31"),t(x"00"),t(x"34"),t(x"37"),t(x"00"),t(x"00"),t(x"00"), -- 6
   // t(x"30"),t(x"2E"),t(x"32"),t(x"35"),t(x"36"),t(x"38"),t(x"1B"),t(x"00"),t(x"1B"),t(x"2B"),t(x"33"),t(x"2D"),t(x"2A"),t(x"39"),t(x"00"),t(x"00"), -- 7
   // t(x"00"),t(x"00"),t(x"00"),t(x"17") -- 8
   // );


   //  7 bits to reduce logic count
   reg [6:0]         kbUnshifted[0 : 131];
   reg [6:0]         kbShifted[0 : 131];

   initial
     begin
        kbUnshifted[0] <= 7'b0000000;
        kbUnshifted[1] <= 7'b0011001;
        kbUnshifted[2] <= 7'b0000000;
        kbUnshifted[3] <= 7'b0000000;
        kbUnshifted[4] <= 7'b0010011;
        kbUnshifted[5] <= 7'b0010001;
        kbUnshifted[6] <= 7'b0010010;
        kbUnshifted[7] <= 7'b0011100;
        kbUnshifted[8] <= 7'b0000000;
        kbUnshifted[9] <= 7'b0011010;
        kbUnshifted[10] <= 7'b0011000;
        kbUnshifted[11] <= 7'b0010110;
        kbUnshifted[12] <= 7'b0000000;
        kbUnshifted[13] <= 7'b0001001;
        kbUnshifted[14] <= 7'b1100000;
        kbUnshifted[15] <= 7'b0000000;
        kbUnshifted[16] <= 7'b0000000;
        kbUnshifted[17] <= 7'b0000000;
        kbUnshifted[18] <= 7'b0000000;
        kbUnshifted[19] <= 7'b0000000;
        kbUnshifted[20] <= 7'b0000000;
        kbUnshifted[21] <= 7'b1110001;
        kbUnshifted[22] <= 7'b0110001;
        kbUnshifted[23] <= 7'b0000000;
        kbUnshifted[24] <= 7'b0000000;
        kbUnshifted[25] <= 7'b0000000;
        kbUnshifted[26] <= 7'b1111010;
        kbUnshifted[27] <= 7'b1110011;
        kbUnshifted[28] <= 7'b1100001;
        kbUnshifted[29] <= 7'b1110111;
        kbUnshifted[30] <= 7'b0110010;
        kbUnshifted[31] <= 7'b0000000;
        kbUnshifted[32] <= 7'b0000000;
        kbUnshifted[33] <= 7'b1100011;
        kbUnshifted[34] <= 7'b1111000;
        kbUnshifted[35] <= 7'b1100100;
        kbUnshifted[36] <= 7'b1100101;
        kbUnshifted[37] <= 7'b0110100;
        kbUnshifted[38] <= 7'b0110011;
        kbUnshifted[39] <= 7'b0000000;
        kbUnshifted[40] <= 7'b0000000;
        kbUnshifted[41] <= 7'b0100000;
        kbUnshifted[42] <= 7'b1110110;
        kbUnshifted[43] <= 7'b1100110;
        kbUnshifted[44] <= 7'b1110100;
        kbUnshifted[45] <= 7'b1110010;
        kbUnshifted[46] <= 7'b0110101;
        kbUnshifted[47] <= 7'b0000000;
        kbUnshifted[48] <= 7'b0000000;
        kbUnshifted[49] <= 7'b1101110;
        kbUnshifted[50] <= 7'b1100010;
        kbUnshifted[51] <= 7'b1101000;
        kbUnshifted[52] <= 7'b1100111;
        kbUnshifted[53] <= 7'b1111001;
        kbUnshifted[54] <= 7'b0110110;
        kbUnshifted[55] <= 7'b0000000;
        kbUnshifted[56] <= 7'b0000000;
        kbUnshifted[57] <= 7'b0000000;
        kbUnshifted[58] <= 7'b1101101;
        kbUnshifted[59] <= 7'b1101010;
        kbUnshifted[60] <= 7'b1110101;
        kbUnshifted[61] <= 7'b0110111;
        kbUnshifted[62] <= 7'b0111000;
        kbUnshifted[63] <= 7'b0000000;
        kbUnshifted[64] <= 7'b0000000;
        kbUnshifted[65] <= 7'b0101100;
        kbUnshifted[66] <= 7'b1101011;
        kbUnshifted[67] <= 7'b1101001;
        kbUnshifted[68] <= 7'b1101111;
        kbUnshifted[69] <= 7'b0110000;
        kbUnshifted[70] <= 7'b0111001;
        kbUnshifted[71] <= 7'b0000000;
        kbUnshifted[72] <= 7'b0000000;
        kbUnshifted[73] <= 7'b0101110;
        kbUnshifted[74] <= 7'b0101111;
        kbUnshifted[75] <= 7'b1101100;
        kbUnshifted[76] <= 7'b0111011;
        kbUnshifted[77] <= 7'b1110000;
        kbUnshifted[78] <= 7'b0101101;
        kbUnshifted[79] <= 7'b0000000;
        kbUnshifted[80] <= 7'b0000000;
        kbUnshifted[81] <= 7'b0000000;
        kbUnshifted[82] <= 7'b0100111;
        kbUnshifted[83] <= 7'b0000000;
        kbUnshifted[84] <= 7'b1011011;
        kbUnshifted[85] <= 7'b0111101;
        kbUnshifted[86] <= 7'b0000000;
        kbUnshifted[87] <= 7'b0000000;
        kbUnshifted[88] <= 7'b0000000;
        kbUnshifted[89] <= 7'b0000000;
        kbUnshifted[90] <= 7'b0001101;
        kbUnshifted[91] <= 7'b1011101;
        kbUnshifted[92] <= 7'b0000000;
        kbUnshifted[93] <= 7'b0000000;
        kbUnshifted[94] <= 7'b0000000;
        kbUnshifted[95] <= 7'b0000000;
        kbUnshifted[96] <= 7'b0000000;
        kbUnshifted[97] <= 7'b0000000;
        kbUnshifted[98] <= 7'b0000000;
        kbUnshifted[99] <= 7'b0000000;
        kbUnshifted[100] <= 7'b0000000;
        kbUnshifted[101] <= 7'b0000000;
        kbUnshifted[102] <= 7'b0001000;
        kbUnshifted[103] <= 7'b0000000;
        kbUnshifted[104] <= 7'b0000000;
        kbUnshifted[105] <= 7'b0110001;
        kbUnshifted[106] <= 7'b0000000;
        kbUnshifted[107] <= 7'b0110100;
        kbUnshifted[108] <= 7'b0110111;
        kbUnshifted[109] <= 7'b0000000;
        kbUnshifted[110] <= 7'b0000000;
        kbUnshifted[111] <= 7'b0000000;
        kbUnshifted[112] <= 7'b0110000;
        kbUnshifted[113] <= 7'b0101110;
        kbUnshifted[114] <= 7'b0110010;
        kbUnshifted[115] <= 7'b0110101;
        kbUnshifted[116] <= 7'b0110110;
        kbUnshifted[117] <= 7'b0111000;
        kbUnshifted[118] <= 7'b0000011;
        kbUnshifted[119] <= 7'b0000000;
        kbUnshifted[120] <= 7'b0011011;
        kbUnshifted[121] <= 7'b0101011;
        kbUnshifted[122] <= 7'b0110011;
        kbUnshifted[123] <= 7'b0101101;
        kbUnshifted[124] <= 7'b0101010;
        kbUnshifted[125] <= 7'b0111001;
        kbUnshifted[126] <= 7'b0000000;
        kbUnshifted[127] <= 7'b0000000;
        kbUnshifted[128] <= 7'b0000000;
        kbUnshifted[129] <= 7'b0000000;
        kbUnshifted[130] <= 7'b0000000;
        kbUnshifted[131] <= 7'b0010111;
     end


   initial
     begin
        kbShifted[0] <= 7'b0000000;
        kbShifted[1] <= 7'b0011001;
        kbShifted[2] <= 7'b0000000;
        kbShifted[3] <= 7'b0000000;
        kbShifted[4] <= 7'b0010011;
        kbShifted[5] <= 7'b0010001;
        kbShifted[6] <= 7'b0010010;
        kbShifted[7] <= 7'b0011100;
        kbShifted[8] <= 7'b0000000;
        kbShifted[9] <= 7'b0011010;
        kbShifted[10] <= 7'b0011000;
        kbShifted[11] <= 7'b0010110;
        kbShifted[12] <= 7'b0000000;
        kbShifted[13] <= 7'b0001001;
        kbShifted[14] <= 7'b0000000;
        kbShifted[15] <= 7'b0000000;
        kbShifted[16] <= 7'b0000000;
        kbShifted[17] <= 7'b0000000;
        kbShifted[18] <= 7'b0000000;
        kbShifted[19] <= 7'b0000000;
        kbShifted[20] <= 7'b0000000;
        kbShifted[21] <= 7'b1010001;
        kbShifted[22] <= 7'b0100001;
        kbShifted[23] <= 7'b0000000;
        kbShifted[24] <= 7'b0000000;
        kbShifted[25] <= 7'b0000000;
        kbShifted[26] <= 7'b1011010;
        kbShifted[27] <= 7'b1010011;
        kbShifted[28] <= 7'b1000001;
        kbShifted[29] <= 7'b1010111;
        kbShifted[30] <= 7'b0100010;
        kbShifted[31] <= 7'b0000000;
        kbShifted[32] <= 7'b0000000;
        kbShifted[33] <= 7'b1000011;
        kbShifted[34] <= 7'b1011000;
        kbShifted[35] <= 7'b1000100;
        kbShifted[36] <= 7'b1000101;
        kbShifted[37] <= 7'b0100100;
        kbShifted[38] <= 7'b0100011;
        kbShifted[39] <= 7'b0000000;
        kbShifted[40] <= 7'b0000000;
        kbShifted[41] <= 7'b0100000;
        kbShifted[42] <= 7'b1010110;
        kbShifted[43] <= 7'b1000110;
        kbShifted[44] <= 7'b1010100;
        kbShifted[45] <= 7'b1010010;
        kbShifted[46] <= 7'b0100101;
        kbShifted[47] <= 7'b0000000;
        kbShifted[48] <= 7'b0000000;
        kbShifted[49] <= 7'b1001110;
        kbShifted[50] <= 7'b1000010;
        kbShifted[51] <= 7'b1001000;
        kbShifted[52] <= 7'b1000111;
        kbShifted[53] <= 7'b1011001;
        kbShifted[54] <= 7'b1011110;
        kbShifted[55] <= 7'b0000000;
        kbShifted[56] <= 7'b0000000;
        kbShifted[57] <= 7'b0000000;
        kbShifted[58] <= 7'b1001101;
        kbShifted[59] <= 7'b1001010;
        kbShifted[60] <= 7'b1010101;
        kbShifted[61] <= 7'b0100110;
        kbShifted[62] <= 7'b0101010;
        kbShifted[63] <= 7'b0000000;
        kbShifted[64] <= 7'b0000000;
        kbShifted[65] <= 7'b0111100;
        kbShifted[66] <= 7'b1001011;
        kbShifted[67] <= 7'b1001001;
        kbShifted[68] <= 7'b1001111;
        kbShifted[69] <= 7'b0101001;
        kbShifted[70] <= 7'b0101000;
        kbShifted[71] <= 7'b0000000;
        kbShifted[72] <= 7'b0000000;
        kbShifted[73] <= 7'b0111110;
        kbShifted[74] <= 7'b0111111;
        kbShifted[75] <= 7'b1001100;
        kbShifted[76] <= 7'b0111010;
        kbShifted[77] <= 7'b1010000;
        kbShifted[78] <= 7'b1011111;
        kbShifted[79] <= 7'b0000000;
        kbShifted[80] <= 7'b0000000;
        kbShifted[81] <= 7'b0000000;
        kbShifted[82] <= 7'b1000000;
        kbShifted[83] <= 7'b0000000;
        kbShifted[84] <= 7'b1111011;
        kbShifted[85] <= 7'b0101011;
        kbShifted[86] <= 7'b0000000;
        kbShifted[87] <= 7'b0000000;
        kbShifted[88] <= 7'b0000000;
        kbShifted[89] <= 7'b0000000;
        kbShifted[90] <= 7'b0001101;
        kbShifted[91] <= 7'b1111101;
        kbShifted[92] <= 7'b0000000;
        kbShifted[93] <= 7'b0000000;
        kbShifted[94] <= 7'b0000000;
        kbShifted[95] <= 7'b0000000;
        kbShifted[96] <= 7'b0000000;
        kbShifted[97] <= 7'b0000000;
        kbShifted[98] <= 7'b0000000;
        kbShifted[99] <= 7'b0000000;
        kbShifted[100] <= 7'b0000000;
        kbShifted[101] <= 7'b0000000;
        kbShifted[102] <= 7'b0001000;
        kbShifted[103] <= 7'b0000000;
        kbShifted[104] <= 7'b0000000;
        kbShifted[105] <= 7'b0110001;
        kbShifted[106] <= 7'b0000000;
        kbShifted[107] <= 7'b0110100;
        kbShifted[108] <= 7'b0110111;
        kbShifted[109] <= 7'b0000000;
        kbShifted[110] <= 7'b0000000;
        kbShifted[111] <= 7'b0000000;
        kbShifted[112] <= 7'b0110000;
        kbShifted[113] <= 7'b0101110;
        kbShifted[114] <= 7'b0110010;
        kbShifted[115] <= 7'b0110101;
        kbShifted[116] <= 7'b0110110;
        kbShifted[117] <= 7'b0111000;
        kbShifted[118] <= 7'b0001100;
        kbShifted[119] <= 7'b0000000;
        kbShifted[120] <= 7'b0011011;
        kbShifted[121] <= 7'b0101011;
        kbShifted[122] <= 7'b0110011;
        kbShifted[123] <= 7'b0101101;
        kbShifted[124] <= 7'b0101010;
        kbShifted[125] <= 7'b0111001;
        kbShifted[126] <= 7'b0000000;
        kbShifted[127] <= 7'b0000000;
        kbShifted[128] <= 7'b0000000;
        kbShifted[129] <= 7'b0000000;
        kbShifted[130] <= 7'b0000000;
        kbShifted[131] <= 7'b0010111;
     end

   assign dispAddr_xx = ((dispAddr));
   assign cursAddr_xx = ((cursAddr));

   // DISPLAY ROM AND RAM

   generate
      if (EXTENDED_CHARSET == 1)
        ROM #(11, 8, "../mem/CGAFontBold.mem") fontRom // 256 chars (2K)
          (
           .address(charAddr),
           .clock(clk),
           .q(charData)
           );
      else
        ROM #(10, 8, "../mem/CGAFontBoldReduced.mem") fontRom  // 128 chars (1K)
          (
           .address(charAddr[9:0]),
           .clock(clk),
           .q(charData)
           );
   endgenerate

   generate
      if (CHARS_PER_SCREEN >1024)
        DisplayRam #(11,8) dispCharRam // For 80x25 display character storage
          (
           .clock(clk),
           .address_b(cursAddr_xx[10:0]),
           .data_b(dispCharWRData),
           .q_b(dispCharRDData),
           .wren_b(dispWR),
           .address_a(dispAddr_xx[10:0]),
           .data_a(8'h00),
           .q_a(dispCharData),
           .wren_a(1'b0)
           );
      else
        DisplayRam #(10,8) dispCharRam  // For 40x25 display character storage
          (
           .clock(clk),
           .address_b(cursAddr_xx[9:0]),
           .data_b(dispCharWRData),
           .q_b(dispCharRDData),
           .wren_b(dispWR),
           .address_a(dispAddr_xx[9:0]),
           .data_a(8'h00),
           .q_a(dispCharData),
           .wren_a(1'b0)
           );
   endgenerate

   generate
      if (COLOUR_ATTS_ENABLED == 1)
        if (CHARS_PER_SCREEN > 1024)
          DisplayRam #(11,8) dispAttRam  // For 80x25 display attribute storage
            (
             .clock(clk),
             .address_b(cursAddr_xx[10:0]),
             .data_b(dispAttWRData),
             .q_b(dispAttRDData),
             .wren_b(dispWR),
             .address_a(dispAddr_xx[10:0]),
             .data_a(8'h00),
             .q_a(dispAttData),
             .wren_a(1'b0)
             );
        else
          DisplayRam #(10,8) dispAttRam  // For 4x25 display attribute storage
            (
             .clock(clk),
             .address_b(cursAddr_xx[9:0]),
             .data_b(dispAttWRData),
             .q_b(dispAttRDData),
             .wren_b(dispWR),
             .address_a(dispAddr_xx[9:0]),
             .data_a(8'h00),
             .q_a(dispAttData),
             .wren_a(1'b0)
             );
      else
        assign dispAttData = dispAttWRData; // If no attribute RAM then two colour output on RGB pins as defined by default/esc sequence
   endgenerate

   assign FNkeys = FNkeysSig;
   assign FNtoggledKeys = FNtoggledKeysSig;
   assign charAddr = {dispCharData,charScanLine[VERT_PIXEL_SCANLINES + 1:VERT_PIXEL_SCANLINES - 1]};


   //assign dispAddr = ((startAddr + charHoriz + ((charVert * HORIZ_CHARS)))) % CHARS_PER_SCREEN;
   //assign cursAddr = ((startAddr + cursorHoriz + ((cursorVert * HORIZ_CHARS)))) % CHARS_PER_SCREEN;
   reg [11:0] tmpDispAddr;
   reg [11:0] tmpCursAddr;
   always @(*) begin
      tmpDispAddr = startAddr + charHoriz + (charVert * HORIZ_CHARS);
      dispAddr = (tmpDispAddr >= CHARS_PER_SCREEN) ? tmpDispAddr - CHARS_PER_SCREEN : tmpDispAddr;
      tmpCursAddr = startAddr + cursorHoriz + (cursorVert * HORIZ_CHARS);
      cursAddr = (tmpCursAddr >= CHARS_PER_SCREEN) ? tmpCursAddr - CHARS_PER_SCREEN : tmpCursAddr;
   end

   assign sync = vSync & hSync;
   // composite sync for mono video out
   // SCREEN RENDERING
   always @(posedge clk) begin
      if(horizCount < CLOCKS_PER_SCANLINE) begin
         horizCount <= horizCount + 1;
         if((horizCount < DISPLAY_LEFT_CLOCK) || (horizCount >= ((DISPLAY_LEFT_CLOCK + HORIZ_CHARS * CLOCKS_PER_PIXEL * 8)))) begin
            hActive <= 1'b 0;
         end
         else begin
            hActive <= 1'b 1;
         end
      end
      else begin
         horizCount <= {12{1'b0}};
         pixelCount <= {3{1'b0}};
         charHoriz <= 0;
         if(vertLineCount > ((VERT_SCANLINES - 1))) begin
            vertLineCount <= {10{1'b0}};
         end
         else begin
            if(vertLineCount < DISPLAY_TOP_SCANLINE || vertLineCount > ((DISPLAY_TOP_SCANLINE + 8 * VERT_PIXEL_SCANLINES * VERT_CHARS - 1))) begin
               vActive <= 1'b 0;
               charVert <= 0;
               charScanLine <= {4{1'b0}};
            end
            else begin
               vActive <= 1'b 1;
               if(charScanLine == ((VERT_PIXEL_SCANLINES * 8 - 1))) begin
                  charScanLine <= {4{1'b0}};
                  charVert <= charVert + 1;
               end
               else begin
                  if(vertLineCount != DISPLAY_TOP_SCANLINE) begin
                     charScanLine <= charScanLine + 1;
                  end
               end
            end
            vertLineCount <= vertLineCount + 1;
         end
      end
      if(horizCount < HSYNC_CLOCKS) begin
         hSync <= H_SYNC_ACTIVE;
      end
      else begin
         hSync <=  ~H_SYNC_ACTIVE;
      end
      if(vertLineCount < VSYNC_SCANLINES) begin
         vSync <= V_SYNC_ACTIVE;
      end
      else begin
         vSync <=  ~V_SYNC_ACTIVE;
      end
      if(hActive == 1'b 1 && vActive == 1'b 1) begin
         if(pixelClockCount < ((CLOCKS_PER_PIXEL - 1))) begin
            pixelClockCount <= pixelClockCount + 1;
         end
         else begin
            pixelClockCount <= {4{1'b0}};
            if(cursorOn == 1'b 1 && cursorVert == charVert && cursorHoriz == charHoriz && charScanLine == ((VERT_PIXEL_SCANLINES * 8 - 1))) begin
               // Cursor (use current colour because cursor cell not yet written to)
               if(dispAttData[3] == 1'b 1) begin
                  // BRIGHT
                  videoR0 <= dispAttWRData[0];
                  videoG0 <= dispAttWRData[1];
                  videoB0 <= dispAttWRData[2];
               end
               else begin
                  videoR0 <= 1'b 0;
                  videoG0 <= 1'b 0;
                  videoB0 <= 1'b 0;
               end
               videoR1 <= dispAttWRData[0];
               videoG1 <= dispAttWRData[1];
               videoB1 <= dispAttWRData[2];
               video <= 1'b 1;
               // Monochrome video out
            end
            else begin
               if(charData[7 - pixelCount] == 1'b 1) begin
                  // Foreground
                  if(dispAttData[3:0] == 4'b 1000) begin
                     // special case = GREY
                     videoR0 <= 1'b 1;
                     videoG0 <= 1'b 1;
                     videoB0 <= 1'b 1;
                     videoR1 <= 1'b 0;
                     videoG1 <= 1'b 0;
                     videoB1 <= 1'b 0;
                  end
                  else begin
                     if(dispAttData[3] == 1'b 1) begin
                        // BRIGHT
                        videoR0 <= dispAttData[0];
                        videoG0 <= dispAttData[1];
                        videoB0 <= dispAttData[2];
                     end
                     else begin
                        videoR0 <= 1'b 0;
                        videoG0 <= 1'b 0;
                        videoB0 <= 1'b 0;
                     end
                     videoR1 <= dispAttData[0];
                     videoG1 <= dispAttData[1];
                     videoB1 <= dispAttData[2];
                  end
               end
               else begin
                  // Background
                  if(dispAttData[7:4] == 4'b 1000) begin
                     // special case = GREY
                     videoR0 <= 1'b 1;
                     videoG0 <= 1'b 1;
                     videoB0 <= 1'b 1;
                     videoR1 <= 1'b 0;
                     videoG1 <= 1'b 0;
                     videoB1 <= 1'b 0;
                  end
                  else begin
                     if(dispAttData[7] == 1'b 1) begin
                        // BRIGHT
                        videoR0 <= dispAttData[4];
                        videoG0 <= dispAttData[5];
                        videoB0 <= dispAttData[6];
                     end
                     else begin
                        videoR0 <= 1'b 0;
                        videoG0 <= 1'b 0;
                        videoB0 <= 1'b 0;
                     end
                     videoR1 <= dispAttData[4];
                     videoG1 <= dispAttData[5];
                     videoB1 <= dispAttData[6];
                  end
               end
               video <= charData[7 - pixelCount];
               // Monochrome video out
            end
            if(pixelCount == 6) begin
               // move output pipeline back by 1 clock to allow readout on posedge
               charHoriz <= charHoriz + 1;
            end
            pixelCount <= pixelCount + 1;
         end
      end
      else begin
         videoR0 <= 1'b 0;
         videoG0 <= 1'b 0;
         videoB0 <= 1'b 0;
         videoR1 <= 1'b 0;
         videoG1 <= 1'b 0;
         videoB1 <= 1'b 0;
         video <= 1'b 0;
         // Monochrome video out
         pixelClockCount <= {4{1'b0}};
      end
   end

   // Hardware cursor blink
   always @(posedge clk) begin
      if(cursBlinkCount < 49999999) begin
         cursBlinkCount <= cursBlinkCount + 1;
      end
      else begin
         cursBlinkCount <= {26{1'b0}};
      end
      if(cursBlinkCount < 25000000) begin
         cursorOn <= 1'b 0;
      end
      else begin
         cursorOn <= 1'b 1;
      end
   end

   // minimal 6850 compatibility
   assign statusReg[0] = kbInPointer == kbReadPointer ? 1'b 0 : 1'b 1;
   assign statusReg[1] = dispByteWritten == dispByteSent ? 1'b 1 : 1'b 0;
   assign statusReg[2] = 1'b 0;
   //n_dcd;
   assign statusReg[3] = 1'b 0;
   //unused
   assign statusReg[6:4] = 3'b000;
   //n_cts;
   assign statusReg[7] =  ~((n_int_internal));
   // interrupt mask
   assign n_int = n_int_internal;
   assign n_int_internal = (kbInPointer != kbReadPointer) && controlReg[7] == 1'b 1 ? 1'b 0 : (dispByteWritten == dispByteSent) && controlReg[6] == 1'b 0 && controlReg[5] == 1'b 1 ? 1'b 0 : 1'b 1;
   assign kbBuffCount = kbInPointer >= kbReadPointer ? 0 + kbInPointer - kbReadPointer : 8 + kbInPointer - kbReadPointer;
   assign n_rts = kbBuffCount > 4 ? 1'b 1 : 1'b 0;
   // write of xxxxxx11 to control reg will reset
   always @(posedge clk) begin
      if(n_wr == 1'b 0 && dataIn[1:0] == 2'b 11 && regSel == 1'b 0) begin
         func_reset <= 1'b 1;
      end
      else begin
         func_reset <= 1'b 0;
      end
   end

   always @(negedge n_rd or posedge func_reset) begin
      if(func_reset == 1'b 1) begin
         kbReadPointer <= 0;
      end else begin
         // Standard CPU - present data on leading edge of rd
         if(regSel == 1'b 1) begin
            dataOut <= {1'b 0,kbBuffer[kbReadPointer]};
            if(kbInPointer != kbReadPointer) begin
               if(kbReadPointer < 7) begin
                  kbReadPointer <= kbReadPointer + 1;
               end
               else begin
                  kbReadPointer <= 0;
               end
            end
         end
         else begin
            dataOut <= statusReg;
         end
      end
   end

   reg n_wr1;
   reg [7:0] dataIn1;
   reg regSel1;
   
   always @(posedge clk) begin
      n_wr1 <= n_wr;
      dataIn1 <= dataIn;
      regSel1 <= regSel;      
      // Standard CPU - capture data on trailing edge of wr
      if (n_wr1 == 1'b0 && n_wr == 1'b1) begin
         if(regSel1 == 1'b 1) begin
            if(dispByteWritten == dispByteSent) begin
               dispByteWritten <=  ~dispByteWritten;
               dispByteLatch <= dataIn1;
            end
         end
         else begin
            controlReg <= dataIn1;
         end
      end
   end

   // PROCESS DATA FROM PS2 KEYBOARD



   // IceStorm cannot infer bidirectional I/Os

`ifdef use_sb_io
   SB_IO
     #(
       .PIN_TYPE(6'b 1010_01)
       )
   ps2_clk_buffer
     (
      .PACKAGE_PIN(ps2Clk),
      .OUTPUT_ENABLE(!ps2ClkOut),
      .D_OUT_0(1'b0),
      .D_IN_0(ps2ClkIn)
      );
   SB_IO
     #(
       .PIN_TYPE(6'b 1010_01)
       )
   ps2_data_buffer
     (
      .PACKAGE_PIN(ps2Data),
      .OUTPUT_ENABLE(!ps2DataOut),
      .D_OUT_0(1'b0),
      .D_IN_0(ps2DataIn)
      );
`else
   assign ps2Clk = ps2ClkOut == 1'b0 ? ps2ClkOut : 1'bZ;
   assign ps2ClkIn = ps2Clk;
   assign ps2Data = ps2DataOut == 1'b 0 ? ps2DataOut : 1'b Z;
   assign ps2DataIn = ps2Data;
`endif

   // PS2 clock de-glitcher - important because the FPGA is very sensistive
   // Filtered clock will not switch low to high until there is 50 more high samples than lows
   // hysteresis will then not switch high to low until there is 50 more low samples than highs.
   // Introduces a minor (1uS) delay with 50MHz clock
   always @(posedge clk) begin
      if(ps2ClkIn == 1'b 1 && ps2ClkFilter == 50) begin
         ps2ClkFiltered <= 1'b 1;
      end
      if(ps2ClkIn == 1'b 1 && ps2ClkFilter != 50) begin
         ps2ClkFilter <= ps2ClkFilter + 1;
      end
      if(ps2ClkIn == 1'b 0 && ps2ClkFilter == 0) begin
         ps2ClkFiltered <= 1'b 0;
      end
      if(ps2ClkIn == 1'b 0 && ps2ClkFilter != 0) begin
         ps2ClkFilter <= ps2ClkFilter - 1;
      end
   end

   always @(posedge clk) begin : P1
      // 11 bits
      // start(0) b0 b1 b2 b3 b4 b5 b6 b7 parity(odd) stop(1)

      ps2PrevClk <= ps2ClkFiltered;
      if(func_reset == 1'b 1) begin
         // reset keyboard pointers
         kbInPointer <= 0;
      end
      if(n_kbWR == 1'b 0 && kbWriteTimer < 25000) begin
         ps2WriteClkCount <= 0;
         kbWRParity <= 1'b 1;
         kbWriteTimer <= kbWriteTimer + 1;
         // wait
      end
      else if(n_kbWR == 1'b 0 && kbWriteTimer < 50000) begin
         ps2ClkOut <= 1'b 0;
         kbWriteTimer <= kbWriteTimer + 1;
      end
      else if(n_kbWR == 1'b 0 && kbWriteTimer < 75000) begin
         ps2DataOut <= 1'b 0;
         kbWriteTimer <= kbWriteTimer + 1;
      end
      else if(n_kbWR == 1'b 0 && kbWriteTimer == 75000) begin
         ps2ClkOut <= 1'b 1;
         kbWriteTimer <= kbWriteTimer + 1;
      end
      else if(n_kbWR == 1'b 0 && kbWriteTimer < 76000) begin
         kbWriteTimer <= kbWriteTimer + 1;
      end
      else if(n_kbWR == 1'b 1 && ps2PrevClk == 1'b 1 && ps2ClkFiltered == 1'b 0) begin
         // start of high-to-low cleaned ps2 clock
         kbWatchdogTimer <= 0;
         if(ps2ClkCount == 0) begin
            // start
            ps2Byte <= {8{1'b0}};
            ps2ClkCount <= ps2ClkCount + 1;
         end
         else if(ps2ClkCount < 9) begin
            // data
            ps2Byte <= {ps2DataIn,ps2Byte[7:1]};
            ps2ClkCount <= ps2ClkCount + 1;
         end
         else if(ps2ClkCount == 9) begin
            // parity - use this time to decode
            if((ps2Byte < 132)) begin
               if(ps2Shift == 1'b 0) begin
                  ps2ConvertedByte <= kbUnshifted[ps2Byte];
               end
               else begin
                  ps2ConvertedByte <= kbShifted[ps2Byte];
               end
            end
            else begin
               ps2ConvertedByte <= {7{1'b0}};
            end
            ps2ClkCount <= ps2ClkCount + 1;
         end
         else begin
            // stop bit - use this time to store
            // FN1-FN10 keys return values 0x11-0x1A. They are not presented as ASCII codes through
            // the virtual UART but instead toggle the FNkeys, FNtoggledKeys outputs.
            // F11, F12 are not included because we need code 0x1B for ESC
            if(ps2ConvertedByte > 8'h 10 && ps2ConvertedByte < 8'h 1B) begin
               if(ps2PreviousByte != 8'h F0) begin
                  FNtoggledKeysSig[ps2ConvertedByte - 16] <= FNtoggledKeysSig[ps2ConvertedByte - 16];
                  FNkeysSig[ps2ConvertedByte - 16] <= 1'b 1;
               end
               else begin
                  FNkeysSig[ps2ConvertedByte - 16] <= 1'b 0;
               end
               // left SHIFT or right SHIFT pressed
            end
            else if(ps2Byte == 8'h 12 || ps2Byte == 8'h 59) begin
               if(ps2PreviousByte != 8'h F0) begin
                  ps2Shift <= 1'b 1;
               end
               else begin
                  ps2Shift <= 1'b 0;
               end
               // CTRL pressed
            end
            else if(ps2Byte == 8'h 14) begin
               if(ps2PreviousByte != 8'h F0) begin
                  ps2Ctrl <= 1'b 1;
               end
               else begin
                  ps2Ctrl <= 1'b 0;
               end
               // Self-test passed (after power-up).
               // Send SET-LEDs command to establish SCROLL, CAPS AND NUM
            end
            else if(ps2Byte == 8'h AA) begin
               ps2WriteByte <= 8'h ED;
               ps2WriteByte2[0] <= ps2Scroll;
               ps2WriteByte2[1] <= ps2Num;
               ps2WriteByte2[2] <= ps2Caps;
               ps2WriteByte2[7:3] <= 5'b 00000;
               n_kbWR <= 1'b 0;
               kbWriteTimer <= 0;
               // SCROLL-LOCK pressed - set flags and
               // update LEDs
            end
            else if(ps2Byte == 8'h 7E) begin
               if(ps2PreviousByte != 8'h F0) begin
                  ps2Scroll <=  ~ps2Scroll;
                  ps2WriteByte <= 8'h ED;
                  ps2WriteByte2[0] <=  ~ps2Scroll;
                  ps2WriteByte2[1] <= ps2Num;
                  ps2WriteByte2[2] <= ps2Caps;
                  ps2WriteByte2[7:3] <= 5'b 00000;
                  n_kbWR <= 1'b 0;
                  kbWriteTimer <= 0;
               end
               // NUM-LOCK pressed - set flags and
               // update LEDs
            end
            else if(ps2Byte == 8'h 77) begin
               if(ps2PreviousByte != 8'h F0) begin
                  ps2Num <=  ~ps2Num;
                  ps2WriteByte <= 8'h ED;
                  ps2WriteByte2[0] <= ps2Scroll;
                  ps2WriteByte2[1] <=  ~ps2Num;
                  ps2WriteByte2[2] <= ps2Caps;
                  ps2WriteByte2[7:3] <= 5'b 00000;
                  n_kbWR <= 1'b 0;
                  kbWriteTimer <= 0;
               end
               // CAPS-LOCK pressed - set flags and
               // update LEDs
            end
            else if(ps2Byte == 8'h 58) begin
               if(ps2PreviousByte != 8'h F0) begin
                  ps2Caps <=  ~ps2Caps;
                  ps2WriteByte <= 8'h ED;
                  ps2WriteByte2[0] <= ps2Scroll;
                  ps2WriteByte2[1] <= ps2Num;
                  ps2WriteByte2[2] <=  ~ps2Caps;
                  ps2WriteByte2[7:3] <= 5'b 00000;
                  n_kbWR <= 1'b 0;
                  kbWriteTimer <= 0;
               end
               // ACK (from SET-LEDs)
            end
            else if(ps2Byte == 8'h FA) begin
               if(ps2WriteByte != 8'h FF) begin
                  n_kbWR <= 1'b 0;
                  kbWriteTimer <= 0;
               end
               // ASCII key press - store it in the kbBuffer.
            end
            else if((ps2PreviousByte != 8'h F0) && (ps2ConvertedByte != 8'h 00)) begin
               if(ps2PreviousByte == 8'h E0 && ps2Byte == 8'h 71) begin
                  // DELETE
                  kbBuffer[kbInPointer] <= 7'b 1111111;
                  // 7F
               end
               else if(ps2Ctrl == 1'b 1) begin
                  kbBuffer[kbInPointer] <= {2'b 00,ps2ConvertedByte[4:0]};
               end
               else if(ps2ConvertedByte > 8'h 40 && ps2ConvertedByte < 8'h 5B && ps2Caps == 1'b 1) begin
                  // A-Z but caps lock on so convert to a-z.
                  kbBuffer[kbInPointer] <= ps2ConvertedByte | 7'b 0100000;
               end
               else if(ps2ConvertedByte > 8'h 60 && ps2ConvertedByte < 8'h 7B && ps2Caps == 1'b 1) begin
                  // a-z but caps lock on so convert to A-Z.
                  kbBuffer[kbInPointer] <= ps2ConvertedByte & 7'b 1011111;
               end
               else begin
                  kbBuffer[kbInPointer] <= ps2ConvertedByte;
               end
               if(kbInPointer < 7) begin
                  kbInPointer <= kbInPointer + 1;
               end
               else begin
                  kbInPointer <= 0;
               end
            end
            ps2PreviousByte <= ps2Byte;
            ps2ClkCount <= 0;
         end
         // write to keyboard
      end
      else if(n_kbWR == 1'b 0 && ps2PrevClk == 1'b 1 && ps2ClkFiltered == 1'b 0) begin
         // start of high-to-low cleaned ps2 clock
         kbWatchdogTimer <= 0;
         if(ps2WriteClkCount < 8) begin
            if((ps2WriteByte[ps2WriteClkCount] == 1'b 1)) begin
               ps2DataOut <= 1'b 1;
               kbWRParity <=  ~kbWRParity;
            end
            else begin
               ps2DataOut <= 1'b 0;
            end
            ps2WriteClkCount <= ps2WriteClkCount + 1;
         end
         else if(ps2WriteClkCount == 8) begin
            ps2DataOut <= kbWRParity;
            ps2WriteClkCount <= ps2WriteClkCount + 1;
         end
         else if(ps2WriteClkCount == 9) begin
            ps2WriteClkCount <= ps2WriteClkCount + 1;
            ps2DataOut <= 1'b 1;
         end
         else if(ps2WriteClkCount == 10) begin
            ps2WriteByte <= ps2WriteByte2;
            ps2WriteByte2 <= 8'h FF;
            n_kbWR <= 1'b 1;
            ps2WriteClkCount <= 0;
            ps2DataOut <= 1'b 1;
         end
      end
      else begin
         // COMMUNICATION ERROR
         // if no edge then increment the timer
         // if a large time has elapsed since the last pulse was read then
         // re-sync the keyboard
         if(kbWatchdogTimer > 30000000) begin
            kbWatchdogTimer <= 0;
            ps2ClkCount <= 0;
            if(n_kbWR == 1'b 0) begin
               ps2WriteByte <= 8'h ED;
               ps2WriteByte2[0] <= ps2Scroll;
               ps2WriteByte2[1] <= ps2Num;
               ps2WriteByte2[2] <= ps2Caps;
               ps2WriteByte2[7:3] <= 5'b 00000;
               kbWriteTimer <= 0;
            end
         end
         else begin
            kbWatchdogTimer <= kbWatchdogTimer + 1;
         end
      end
   end

   // PROCESS DATA WRITTEN TO DISPLAY
   always @(posedge clk or negedge n_reset) begin
      if(n_reset == 1'b 0) begin
         dispAttWRData <= DEFAULT_ATT;
      end else begin
         case(dispState)
           idle : begin
              if((escState != processingAdditionalParams) && (dispByteWritten != dispByteSent)) begin
                 dispCharWRData <= dispByteLatch;
                 dispByteSent <=  ~dispByteSent;
              end
              if((escState == processingAdditionalParams) || (dispByteWritten != dispByteSent)) begin
                 if(dispByteLatch == 8'h 07) begin
                    // BEEP
                    // do nothing - ignore
                 end
                 else if(dispByteLatch == 8'h 1B) begin
                    // ESC
                    paramCount <= 0;
                    param1 <= 0;
                    param2 <= 0;
                    param3 <= 0;
                    param4 <= 0;
                    escState <= waitForLeftBracket;
                 end
                 else if(escState == waitForLeftBracket && dispByteLatch == 8'h 5B) begin
                    // ESC[
                    escState <= processingParams;
                    paramCount <= 1;
                 end
                 else if(paramCount == 1 && dispByteLatch == 8'h 48 && param1 == 0) begin
                    // ESC[H - home
                    cursorVert <= 0;
                    cursorHoriz <= 0;
                    paramCount <= 0;
                 end
                 else if(paramCount == 1 && dispByteLatch == 8'h 4B && param1 == 0) begin
                    // ESC[K - erase EOL
                    cursorVertRestore <= cursorVert;
                    cursorHorizRestore <= cursorHoriz;
                    dispState <= clearLine;
                    paramCount <= 0;
                 end
                 else if(paramCount == 1 && dispByteLatch == 8'h 73 && param1 == 0) begin
                    // ESC[s - save cursor pos
                    savedCursorHoriz <= cursorHoriz;
                    savedCursorVert <= cursorVert;
                    paramCount <= 0;
                 end
                 else if(paramCount == 1 && dispByteLatch == 8'h 75 && param1 == 0) begin
                    // ESC[u - restore cursor pos
                    cursorHoriz <= savedCursorHoriz;
                    cursorVert <= savedCursorVert;
                    paramCount <= 0;
                 end
                 else if(paramCount > 0 && dispByteLatch == 8'h 3B) begin
                    // ESC[{param1};{param2}...
                    paramCount <= paramCount + 1;
                 end
                 else if(paramCount > 0 && dispByteLatch > 8'h 2F && dispByteLatch < 8'h 3A) begin
                    // numeric
                    if(paramCount == 1) begin
                       // ESC[{param1}
                       param1 <= {param1, 1'b0} + {param1, 3'b0} + dispByteLatch[3:0];
                    end
                    else if(paramCount == 2) begin
                       // ESC[{param1};{param2}
                       param2 <= {param2, 1'b0} + {param2, 3'b0} + dispByteLatch[3:0];
                    end
                    else if(paramCount == 3) begin
                       // ESC[{param1};{param2};{param3}
                       param3 <= {param3, 1'b0} + {param3, 3'b0} + dispByteLatch[3:0];
                    end
                    else if(paramCount == 4) begin
                       // ESC[{param1};{param2};{param3};{param4}
                       param4 <= {param4, 1'b0} + {param4, 3'b0} + dispByteLatch[3:0];
                    end
                 end
                 else if(paramCount == 1 && param1 == 2 && dispByteLatch == 8'h 4A) begin
                    // ESC[2J - clear screen
                    cursorVert <= 0;
                    cursorHoriz <= 0;
                    cursorVertRestore <= 0;
                    cursorHorizRestore <= 0;
                    dispState <= clearScreen;
                    paramCount <= 0;
                 end
                 else if(paramCount == 1 && param1 == 0 && dispByteLatch == 8'h 4A) begin
                    // ESC[0J or ESC[J - clear from cursor to end of screen
                    cursorVertRestore <= cursorVert;
                    cursorHorizRestore <= cursorHoriz;
                    dispState <= clearScreen;
                    paramCount <= 0;
                 end
                 else if(paramCount == 1 && dispByteLatch == 8'h 4C) begin
                    // ESC[L - insert line
                    cursorVertRestore <= cursorVert;
                    cursorHorizRestore <= cursorHoriz;
                    cursorHoriz <= 0;
                    paramCount <= 0;
                    if(cursorVert < VERT_CHAR_MAX) begin
                       cursorVert <= VERT_CHAR_MAX - 1;
                       dispState <= insertLine;
                    end
                    else begin
                       dispState <= clearLine;
                    end
                 end
                 else if(paramCount == 1 && dispByteLatch == 8'h 4D) begin
                    // ESC[M - delete line
                    cursorVertRestore <= cursorVert;
                    cursorHorizRestore <= cursorHoriz;
                    cursorHoriz <= 0;
                    paramCount <= 0;
                    if(cursorVert < VERT_CHAR_MAX) begin
                       cursorVert <= cursorVert + 1;
                       dispState <= deleteLine;
                    end
                    else begin
                       dispState <= clearLine;
                    end
                 end
                 else if(paramCount > 0 && dispByteLatch == 8'h 6D) begin
                    // ESC[{param1}m or ESC[{param1};{param2}m- set graphics rendition
                    if(param1 == 0) begin
                       attInverse <= 1'b 0;
                       attBold <= ANSI_DEFAULT_ATT[3];
                       dispAttWRData <= ANSI_DEFAULT_ATT;
                    end
                    if(param1 == 1) begin
                       attBold <= 1'b 1;
                       dispAttWRData[3] <= 1'b 1;
                    end
                    if(param1 == 22) begin
                       attBold <= 1'b 0;
                       dispAttWRData[3] <= 1'b 0;
                    end
                    if(param1 == 7) begin
                       if(attInverse == 1'b 0) begin
                          attInverse <= 1'b 1;
                          dispAttWRData[7:4] <= dispAttWRData[3:0];
                          dispAttWRData[3:0] <= dispAttWRData[7:4];
                       end
                    end
                    if(param1 == 27) begin
                       if(attInverse == 1'b 1) begin
                          attInverse <= 1'b 0;
                          dispAttWRData[7:4] <= dispAttWRData[3:0];
                          dispAttWRData[3:0] <= dispAttWRData[7:4];
                       end
                    end
                    if(param1 > 29 && param1 < 38) begin
                       if(attInverse == 1'b 0) begin
                          dispAttWRData[2:0] <= ((param1 - 30));
                          dispAttWRData[3] <= attBold;
                       end
                       else begin
                          dispAttWRData[6:4] <= ((param1 - 30));
                          dispAttWRData[7] <= attBold;
                       end
                    end
                    if(param1 > 39 && param1 < 48) begin
                       if(attInverse == 1'b 0) begin
                          dispAttWRData[6:4] <= ((param1 - 40));
                          dispAttWRData[7] <= attBold;
                       end
                       else begin
                          dispAttWRData[2:0] <= ((param1 - 40));
                          dispAttWRData[3] <= attBold;
                       end
                    end
                    if(param1 > 89 && param1 < 98) begin
                       if(attInverse == 1'b 0) begin
                          dispAttWRData[2:0] <= ((param1 - 90));
                          dispAttWRData[3] <= 1'b 1;
                       end
                       else begin
                          dispAttWRData[6:4] <= ((param1 - 90));
                          dispAttWRData[7] <= 1'b 1;
                       end
                    end
                    if(param1 > 99 && param1 < 108) begin
                       if(attInverse == 1'b 0) begin
                          dispAttWRData[6:4] <= ((param1 - 100));
                          dispAttWRData[7] <= 1'b 1;
                       end
                       else begin
                          dispAttWRData[2:0] <= ((param1 - 100));
                          dispAttWRData[3] <= 1'b 1;
                       end
                    end
                    // allow for second parameter - must process individually and in sequence
                    if(paramCount > 1) begin
                       param1 <= param2;
                       param2 <= param3;
                       param3 <= param4;
                       paramCount <= paramCount - 1;
                       escState <= processingAdditionalParams;
                    end
                    else begin
                       paramCount <= 0;
                       escState <= none;
                    end
                 end
                 else if(paramCount == 1 && dispByteLatch == 8'h 41) begin
                    // ESC[{param1}A - Cursor up
                    if(param1 == 0 && cursorVert > 0) begin
                       // no param so default to 1
                       cursorVert <= cursorVert - 1;
                    end
                    else if(param1 < cursorVert) begin
                       cursorVert <= cursorVert - param1;
                    end
                    else begin
                       cursorVert <= 0;
                    end
                    paramCount <= 0;
                 end
                 else if(paramCount == 1 && dispByteLatch == 8'h 42) begin
                    // ESC[{param1}B - Cursor down
                    if(param1 == 0 && cursorVert < VERT_CHAR_MAX) begin
                       // no param so default to 1
                       cursorVert <= cursorVert + 1;
                    end
                    else if(((cursorVert + param1)) < VERT_CHAR_MAX) begin
                       cursorVert <= cursorVert + param1;
                    end
                    else begin
                       cursorVert <= VERT_CHAR_MAX;
                    end
                    paramCount <= 0;
                 end
                 else if(paramCount == 1 && dispByteLatch == 8'h 43) begin
                    // ESC[{param1}C - Cursor forward
                    if(param1 == 0 && cursorHoriz < HORIZ_CHAR_MAX) begin
                       // no param so default to 1
                       cursorHoriz <= cursorHoriz + 1;
                    end
                    else if(((cursorHoriz + param1)) < HORIZ_CHAR_MAX) begin
                       cursorHoriz <= cursorHoriz + param1;
                    end
                    else begin
                       cursorHoriz <= HORIZ_CHAR_MAX;
                    end
                    paramCount <= 0;
                 end
                 else if(paramCount == 1 && dispByteLatch == 8'h 44) begin
                    // ESC[{param1}D - Cursor backward
                    if(param1 == 0 && cursorHoriz > 0) begin
                       // no param so default to 1
                       cursorHoriz <= cursorHoriz - 1;
                    end
                    else if(param1 < cursorHoriz) begin
                       cursorHoriz <= cursorHoriz - param1;
                    end
                    else begin
                       cursorHoriz <= 0;
                    end
                    paramCount <= 0;
                 end
                 else if(paramCount == 2 && dispByteLatch == 8'h 48) begin
                    // ESC[{param1};{param2}H
                    if(param1 < 1) begin
                       cursorVert <= 0;
                    end
                    else if(param1 > VERT_CHARS) begin
                       cursorVert <= VERT_CHARS - 1;
                    end
                    else begin
                       cursorVert <= param1 - 1;
                    end
                    if(param2 < 0) begin
                       cursorHoriz <= 0;
                    end
                    else if(param2 > HORIZ_CHARS) begin
                       cursorHoriz <= HORIZ_CHARS - 1;
                    end
                    else begin
                       cursorHoriz <= param2 - 1;
                    end
                    paramCount <= 0;
                 end
                 else begin
                    dispState <= dispWrite;
                    escState <= none;
                    paramCount <= 0;
                 end
              end
           end
           dispWrite : begin
              if(dispCharWRData == 13) begin
                 // CR
                 cursorHoriz <= 0;
                 dispState <= idle;
              end
              else if(dispCharWRData == 10) begin
                 // LF
                 if(cursorVert < VERT_CHAR_MAX) begin
                    // move down to next line
                    cursorVert <= cursorVert + 1;
                    dispState <= idle;
                 end
                 else begin
                    // scroll
                    if(startAddr < ((CHARS_PER_SCREEN - HORIZ_CHARS))) begin
                       startAddr <= startAddr + HORIZ_CHARS;
                    end
                    else begin
                       startAddr <= 0;
                    end
                    cursorHoriz <= 0;
                    cursorHorizRestore <= cursorHoriz;
                    cursorVertRestore <= cursorVert;
                    dispState <= clearLine;
                 end
              end
              else if(dispCharWRData == 12) begin
                 // CLS
                 cursorVert <= 0;
                 cursorHoriz <= 0;
                 cursorHorizRestore <= 0;
                 cursorVertRestore <= 0;
                 dispState <= clearScreen;
              end
              else if(dispCharWRData == 8 || dispCharWRData == 127) begin
                 // BS
                 if(cursorHoriz > 0) begin
                    cursorHoriz <= cursorHoriz - 1;
                 end
                 else if(cursorHoriz == 0 && cursorVert > 0) begin
                    cursorHoriz <= HORIZ_CHAR_MAX;
                    cursorVert <= cursorVert - 1;
                 end
                 dispState <= clearChar;
              end
              else begin
                 // Displayable character
                 dispWR <= 1'b 1;
                 dispState <= dispNextLoc;
              end
           end
           dispNextLoc : begin
              dispWR <= 1'b 0;
              if((cursorHoriz < HORIZ_CHAR_MAX)) begin
                 cursorHoriz <= cursorHoriz + 1;
                 dispState <= idle;
              end
              else begin
                 cursorHoriz <= 0;
                 if(cursorVert < VERT_CHAR_MAX) begin
                    cursorVert <= cursorVert + 1;
                    dispState <= idle;
                 end
                 else begin
                    if(startAddr < ((CHARS_PER_SCREEN - HORIZ_CHARS))) begin
                       startAddr <= startAddr + HORIZ_CHARS;
                    end
                    else begin
                       startAddr <= 0;
                    end
                    cursorHorizRestore <= 0;
                    cursorVertRestore <= cursorVert;
                    dispState <= clearLine;
                 end
              end
           end
           clearLine : begin
              dispCharWRData <= 8'h 20;
              dispWR <= 1'b 1;
              dispState <= clearL2;
           end
           clearL2 : begin
              dispWR <= 1'b 0;
              if((cursorHoriz < HORIZ_CHAR_MAX)) begin
                 cursorHoriz <= cursorHoriz + 1;
                 dispState <= clearLine;
              end
              else begin
                 cursorHoriz <= cursorHorizRestore;
                 cursorVert <= cursorVertRestore;
                 dispState <= idle;
              end
           end
           clearChar : begin
              dispCharWRData <= 8'h 20;
              dispWR <= 1'b 1;
              dispState <= clearC2;
           end
           clearC2 : begin
              dispWR <= 1'b 0;
              dispState <= idle;
           end
           clearScreen : begin
              dispCharWRData <= 8'h 20;
              dispWR <= 1'b 1;
              dispState <= clearS2;
           end
           clearS2 : begin
              dispWR <= 1'b 0;
              if((cursorHoriz < HORIZ_CHAR_MAX)) begin
                 cursorHoriz <= cursorHoriz + 1;
                 dispState <= clearScreen;
              end
              else begin
                 if((cursorVert < VERT_CHAR_MAX)) begin
                    cursorHoriz <= 0;
                    cursorVert <= cursorVert + 1;
                    dispState <= clearScreen;
                 end
                 else begin
                    cursorHoriz <= cursorHorizRestore;
                    cursorVert <= cursorVertRestore;
                    dispState <= idle;
                 end
              end
           end
           insertLine : begin
              cursorVert <= cursorVert + 1;
              dispState <= ins2;
           end
           ins2 : begin
              dispCharWRData <= dispCharRDData;
              dispAttWRData <= dispAttRDData;
              dispWR <= 1'b 1;
              dispState <= ins3;
           end
           ins3 : begin
              dispWR <= 1'b 0;
              if(cursorHoriz < HORIZ_CHAR_MAX) begin
                 // current line still in progress
                 cursorHoriz <= cursorHoriz + 1;
                 cursorVert <= cursorVert - 1;
                 dispState <= insertLine;
              end
              else if(cursorVert == (cursorVertRestore + 1)) begin
                 // current line finished, no more lines to move
                 cursorHoriz <= 0;
                 cursorVert <= cursorVertRestore;
                 dispState <= clearLine;
              end
              else begin
                 // current line finished, do next one
                 cursorHoriz <= 0;
                 cursorVert <= cursorVert - 2;
                 dispState <= insertLine;
              end
           end
           deleteLine : begin
              cursorVert <= cursorVert - 1;
              dispState <= del2;
           end
           del2 : begin
              dispCharWRData <= dispCharRDData;
              dispAttWRData <= dispAttRDData;
              dispWR <= 1'b 1;
              dispState <= del3;
           end
           del3 : begin
              dispWR <= 1'b 0;
              if(cursorHoriz < HORIZ_CHAR_MAX) begin
                 // current line still in progress
                 cursorHoriz <= cursorHoriz + 1;
                 cursorVert <= cursorVert + 1;
                 dispState <= deleteLine;
              end
              else if(cursorVert == (VERT_CHAR_MAX - 1)) begin
                 // current line finished, no more lines to move
                 cursorHoriz <= 0;
                 cursorVert <= VERT_CHAR_MAX;
                 dispState <= clearLine;
              end
              else begin
                 // current line finished, do next one
                 cursorHoriz <= 0;
                 cursorVert <= cursorVert + 2;
                 dispState <= deleteLine;
              end
           end
         endcase
      end
   end


endmodule
