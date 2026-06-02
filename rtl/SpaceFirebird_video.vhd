--
-- A simulation of Space Firebird
--
-- Mike Coates
--
-- version 001 initial release
--
library ieee;
	use ieee.std_logic_1164.all;
	use ieee.std_logic_unsigned.all;
	use ieee.numeric_std.all;

entity SPACEFIREBIRD_VIDEO is
GENERIC (
	CLIP_L : natural := 0;
	CLIP_R : natural := 255
);
port (
	I_Firebird 			: in  std_logic;
	I_Bullet          : in  std_logic;	
	--
	I_HCNT            : in    std_logic_vector(8 downto 0);
	I_VCNT            : in    std_logic_vector(8 downto 0);
	--
	I_FLIP            : in    std_logic;
	I_CREF            : in    std_logic;
	I_STARS           : in    std_logic;
	I_CONT_R          : in    std_logic;
	I_CONT_G          : in    std_logic;
	I_CONT_B          : in    std_logic;
	I_ALRD            : in    std_logic;
	I_ALBU            : in    std_logic;
	--
	I_SPRITE   			: in    std_logic_vector(31 downto 0);
	O_VADDR   			: out   std_logic_vector(6 downto 0);
	--
	dn_addr           : in    std_logic_vector(15 downto 0);
	dn_data           : in    std_logic_vector(7 downto 0);
	dn_wr             : in    std_logic;
	dn_ld	     			: in    std_logic;
	--
	O_RED             : out   std_logic_vector(7 downto 0);
	O_GREEN           : out   std_logic_vector(7 downto 0);
	O_BLUE            : out   std_logic_vector(7 downto 0);
	--
	RESET					: in    std_logic;
	I_PIX      			: in    std_logic_vector(1 downto 0);
	VID_CLK           : in    std_logic;
	SYS_CLK		      : in    std_logic
);
end;

architecture RTL of SPACEFIREBIRD_VIDEO is

	signal bullet_cs		: std_logic;
	signal bullet_addr	: std_logic_vector(7 downto 0);
	signal bullet_data   : std_logic_vector(3 downto 0);
	signal sprite0_cs		: std_logic;
	signal sprite1_cs		: std_logic;
	signal sprite_addr	: std_logic_vector(10 downto 0);
	signal sprite_data   : std_logic_vector(15 downto 0);
	signal colour_cs		: std_logic;
	signal colour_addr   : std_logic_vector(5 downto 0);
	signal colour_data   : std_logic_vector(7 downto 0);
	
	signal star_dis		: std_logic;
	signal star_rng		: std_logic_vector(16 downto 0) := '0' & x"38F6";
	signal SR,SG,SB      : std_logic_vector(7 downto 0);
	signal ALRD, ALBU	   : std_logic;
	signal skipstar 	   : std_logic;

-- Data for two screen lines
	type   pixrow is array (255 downto 0,1 downto 0) of std_logic_vector(5 downto 0);
	signal rowdata : pixrow;

-- states for screen draw
	TYPE Tstate IS (T_IDLE, T_NEXT, T_BLANK, T_LOAD0, T_LOAD1, T_WAIT, T_DRAW_S0, T_DRAW_S1, T_DRAW_B0, T_DRAW_B1);
	SIGNAL state: Tstate;

	signal Bank 		: integer range 0 to 1;
	signal DrawV      : integer range 0 to 223;
	signal vid_addr   : std_logic_vector(6 downto 0);
	signal DrawPixel  : integer range 0 to 7;
	signal BlankPixel : integer range 0 to 255;
	signal R,G,B      : std_logic_vector(7 downto 0);
	
begin
	sprite0_cs <= '1' when dn_addr(15 downto 11) = "01000" else '0'; 		-- 4000-47FF
	sprite1_cs <= '1' when dn_addr(15 downto 11) = "01001" else '0'; 		-- 4800-4FFF
	bullet_cs  <= '1' when dn_addr(15 downto 8)  = "01010000" else '0'; 	-- 5000-50FF
	colour_cs  <= '1' when dn_addr(15 downto 8)  = "01010001" else '0'; 	-- 5100-51FF (repeated 8 times)
	
	O_VADDR     <= vid_addr;
	O_RED       <= R;
	O_GREEN     <= G;
	O_BLUE      <= B;
	
sprite0 : entity work.dpram_difc
	 generic map (
	  addr_width_a => 11,
	  addr_width_b => 11
	 )
	 port map (
	  data_a     => dn_data(7 downto 0),
	  address_a  => dn_addr(10 downto 0),
	  wren_a     => dn_wr and sprite0_cs,
	  enable_a   => sprite0_cs,
	  clock_a    => SYS_CLK,
	  
	  address_b  => sprite_addr,
	  q_b        => sprite_data(7 downto 0),
	  clock_b    => VID_CLK
	 );

sprite1 : entity work.dpram_difc
	 generic map (
	  addr_width_a => 11,
	  addr_width_b => 11
	 )
	 port map (
	  data_a     => dn_data(7 downto 0),
	  address_a  => dn_addr(10 downto 0),
	  wren_a     => dn_wr and sprite1_cs,
	  enable_a   => sprite1_cs,
	  clock_a    => SYS_CLK,
	  
	  address_b  => sprite_addr,
	  q_b        => sprite_data(15 downto 8),
	  clock_b    => VID_CLK
	 );

bullet : entity work.dpram_difc
	 generic map (
	  addr_width_a => 8,
	  data_width_a => 4,
	  addr_width_b => 8,
	  data_width_b => 4
	 )
	 port map (
	  data_a     => dn_data(3 downto 0),
	  address_a  => dn_addr(7 downto 0),
	  wren_a     => dn_wr and bullet_cs,
	  enable_a   => bullet_cs,
	  clock_a    => SYS_CLK,
	  
	  address_b  => bullet_addr,
	  q_b        => bullet_data,
	  clock_b    => VID_CLK
	 );	 

-- colour prom 
colour : entity work.dpram_difc
	 generic map (
	  addr_width_a => 5,
	  addr_width_b => 5
	 )
	 port map (
	  data_a     => dn_data(7 downto 0),
	  address_a  => dn_addr(4 downto 0),
	  wren_a     => dn_wr and colour_cs,
	  enable_a   => colour_cs,
	  clock_a    => SYS_CLK,
	  
	  address_b  => I_CREF & colour_addr(3 downto 0),
	  q_b        => colour_data,
	  clock_b    => VID_CLK
	 );	 
	 
pixel_out : process
	variable RED,GREEN,BLUE : natural range 0 to 255;
	variable Row : natural range 0 to 1;
	variable Bright : natural range 0 to 3;
	begin
		wait until rising_edge(VID_CLK);
		
		if I_VCNT(0)='0' then
			Row := 0;
		else
			Row := 1;
		end if;
				
		case I_PIX is
		
			when "00" =>	
			
						-- Check to see if in visual range
						if I_HCNT >= CLIP_L and I_HCNT <= CLIP_R then
						
							if I_VCNT >= 0 and I_VCNT <= 223 then
							
								colour_addr <= rowdata(to_integer(unsigned(I_HCNT)), Row);

							end if;

						else 
							-- Use colour 0
							colour_addr <= (others => '0');
						end if;
						
			when "01" =>
						-- Stars and background
						
						if RED = 0 and GREEN = 0 AND BLUE = 0 then
						
							R <= SR;
							G <= SG;
							B <= SB;
							
						end if;
						
			when "10" =>							
						-- Brightness is top 2 bits
						case colour_addr(5 downto 4) is
						
							when "00" =>
								RED   := 36 * to_integer(unsigned(colour_data(2 downto 0)));
								GREEN := 36 * to_integer(unsigned(colour_data(5 downto 3)));
								BLUE  := 72 * to_integer(unsigned(colour_data(7 downto 6)));

							when "01" =>
								RED   := 25 * to_integer(unsigned(colour_data(2 downto 0)));
								GREEN := 25 * to_integer(unsigned(colour_data(5 downto 3)));
								BLUE  := 50 * to_integer(unsigned(colour_data(7 downto 6)));
						
							when "10" =>
								RED   := 15 * to_integer(unsigned(colour_data(2 downto 0)));
								GREEN := 15 * to_integer(unsigned(colour_data(5 downto 3)));
								BLUE  := 30 * to_integer(unsigned(colour_data(7 downto 6)));
						
							when "11" =>
								RED   := 10 * to_integer(unsigned(colour_data(2 downto 0)));
								GREEN := 10 * to_integer(unsigned(colour_data(5 downto 3)));
								BLUE  := 20 * to_integer(unsigned(colour_data(7 downto 6)));
								
						end case;

			when "11" => 
						-- Output to display Stars and background
						
						if RED = 0 and GREEN = 0 AND BLUE = 0 then
						
							R <= SR;
							G <= SG;
							B <= SB;
							
						else
						
							R <= std_logic_vector(to_unsigned(RED, 8));
							G <= std_logic_vector(to_unsigned(GREEN, 8));
							B <= std_logic_vector(to_unsigned(BLUE, 8));
						
						end if;
		end case;
		
   end process;
	

----------------------	
-- Object draw routine
----------------------	

RenderScreen : process
 variable POS_V,POS_H : integer range -18 to 255;
 variable OFF_V       : integer range 0 to 7;
 variable ThisPixel   : std_logic_vector(1 downto 0);
 variable CheckH      : integer range -18 to 255;
 variable ColBase	    : std_logic_vector(3 downto 0);
 begin
	wait until rising_edge(VID_CLK);

	IF RESET = '1' THEN
		state <= T_IDLE;
	else
		
		case state is
		
			when T_IDLE =>	
								-- in vertical range
								if (I_VCNT >= 0 and I_VCNT <= 222) or I_VCNT = 261 then		
								
									-- trigger at end of horizontal line ?
									if (I_HCNT = 0) then
									
										-- vertical line to draw
										if I_VCNT = 261 then
											DrawV <= 0;
										else
											DrawV <= to_integer(unsigned(I_VCNT)) + 1;
										end if;
										
										-- Bank to use
										BlankPixel <= 0;
										if I_VCNT(0)='0' then
											Bank <= 1;
										else
											Bank <= 0;
										end if;
										
										-- Start at first object
										vid_addr <= (others => '0');	
										
										state <= T_BLANK;
									end if;
								end if;
								
			when T_BLANK =>
								-- Clear row before use
								rowdata(BlankPixel, Bank) <= (others => '0');
								if (BlankPixel = 255) then
									state <= T_LOAD1;
								else
									BlankPixel <= BlankPixel + 1;
								end if;
				
			when T_NEXT =>
								-- Skip to next sprite (unless this is the last one)
								if (vid_addr = 127) then
									state <= T_IDLE;
								else
									-- Set next sprite
									vid_addr <= vid_addr + 1;
									state <= T_LOAD0;
								end if;

			when T_LOAD0 =>
								-- delay 1 cycle
								state <= T_LOAD1;
								
			when T_LOAD1 =>	
								-- Data for current sprite in I_SPRITE
								
								--	 * Sprite Tile Format
								--	 * ------------------
								--	 *
								--	 * Byte | Bit(s)   | Use
								--	 * -----+-76543210-+----------------
								--	 *  0   | xxxxxxxx | H Pos
								--	 *  1   | xxxxxxxx | V Pos
								--	 *  2   | xxxxxxxx | code (0-FF sprite, 0-3F bullet)
								--	 *  3   | ....xxxx | Palette Bank
								--	 *  3   | ..x..... | bullet
								--	 *  3   | .x...... | sprite
								
								POS_V := to_integer(unsigned(not I_SPRITE(15 downto 8))) - 18;
								
								-- Flipped, mirror position, offset by character width
								if (I_FLIP = '1') then
									if I_SPRITE(30)='1' then
										-- Sprite
										POS_V := (223-7) - POS_V;
									else
										-- Bullet
										POS_V := (223-3) - POS_V;
									end if;
								end if;
								
								ColBase := not I_SPRITE(27 downto 24);
								
								-- FLIP --

								DrawPixel <= 0;
								
								if (I_SPRITE(30)='1' and DrawV >= POS_V and DrawV <= (POS_V + 7)) then		-- sprites are 8 high
									-- Draw a sprite!
									POS_H := to_integer(unsigned(I_SPRITE(7 downto 0))) - 3;
									if (I_FLIP = '0') then
										OFF_V := 7 - (DrawV - POS_V); 
									else
										OFF_V := (DrawV - POS_V); 
										POS_H := 255 - POS_H;
									end if;
									sprite_addr <= not I_SPRITE(23 downto 16) & std_logic_vector(to_unsigned(OFF_V,3))(2 downto 0);
									state <= T_DRAW_S0;
								elsif (I_SPRITE(29)='1' and DrawV >= POS_V and DrawV <= (POS_V + 3)) then	-- bullets are 4 high
									-- Draw a bullet
									POS_H := to_integer(unsigned(I_SPRITE(7 downto 0)));
									if (I_FLIP = '0') then
										OFF_V := (DrawV - POS_V);
									else
										OFF_V := 3 - (DrawV - POS_V);
										POS_H := 255 - POS_H;
									end if;
									bullet_addr <= I_SPRITE(21 downto 16) & std_logic_vector(to_unsigned(OFF_V,3))(1 downto 0);
									state <= T_DRAW_B0;
								else
									state <= T_NEXT;
								end if;
								
			when T_DRAW_S0 =>
								-- delay 1 cycle
								state <= T_DRAW_S1;
								
			when T_DRAW_S1 =>	
								-- loop 8 times for each pixel to copy to the buffer
								case DrawPixel is
								
									when 0 => ThisPixel := sprite_data(0) & sprite_data(8);
									when 1 => ThisPixel := sprite_data(1) & sprite_data(9);
									when 2 => ThisPixel := sprite_data(2) & sprite_data(10);
									when 3 => ThisPixel := sprite_data(3) & sprite_data(11);
									when 4 => ThisPixel := sprite_data(4) & sprite_data(12);
									when 5 => ThisPixel := sprite_data(5) & sprite_data(13);
									when 6 => ThisPixel := sprite_data(6) & sprite_data(14);
									when 7 => ThisPixel := sprite_data(7) & sprite_data(15);
									
								end case;
								
								if (ThisPixel /= "00") then
									-- Set X position
									if (I_FLIP = '0') then
										CheckH := POS_H + DrawPixel;
									else
										CheckH := POS_H - DrawPixel;
									end if;
								
									if CheckH >= CLIP_L and CheckH <= CLIP_R then
										rowdata(CheckH, Bank) <= ColBase & ThisPixel;
									end if;
								end if;
								
								if (DrawPixel = 7) then
									state <= T_NEXT;
								else
									DrawPixel <= DrawPixel + 1;
								end if;

			when T_DRAW_B0 =>
								-- delay 1 cycle
								state <= T_DRAW_B1;
								
			when T_DRAW_B1 =>	
								-- loop 8 times for each pixel to copy to the buffer
								case DrawPixel is
								
									when 0 => ThisPixel(0) := bullet_data(0);
									when 1 => ThisPixel(0) := bullet_data(1);
									when 2 => ThisPixel(0) := bullet_data(2);
									when 3 => ThisPixel(0) := bullet_data(3);
									
									when others => null;
									
								end case;
								
								if (ThisPixel(0) /= '0') then
									-- Set X position
									if (I_FLIP = '0') then
										CheckH := POS_H + DrawPixel;
									else
										CheckH := POS_H + (3 - DrawPixel);
									end if;
								
									if CheckH >= CLIP_L and CheckH <= CLIP_R then
										if I_Bullet = '1' then
											rowdata(CheckH, Bank) <= "00001101"; 	-- Yellow
										else
											rowdata(CheckH, Bank) <= "00001111"; 	-- Red
										end if;
									end if;
								end if;
								
								if (DrawPixel = 3) then
									state <= T_NEXT;
								else
									DrawPixel <= DrawPixel + 1;
								end if;
																	
			when others =>
								-- error occurred!
								state <= T_IDLE;
		end case;
	end if;
	
  end	process;

  --
  -- Star Generator
  --
  
  StarGen : process
 	variable RED,GREEN,BLUE : natural range 0 to 255;
	variable colour : std_logic_vector(5 downto 0);
  begin
		wait until rising_edge(VID_CLK);
		
		-- just before start of visible screen, set things up
		if I_HCNT = 310 and I_VCNT = 260 then
		
			-- Space firebird skips one random number per screen to keep stars static
			skipstar <= I_Firebird;

			-- save controls so affect entire screen
			star_dis <= I_STARS;
			ALRD <= I_ALRD;
			ALBU <= I_ALBU;
			
		end if;
		
		-- visual screen 0-223, off screen 224-255
		if I_HCNT >= CLIP_L and I_HCNT <= CLIP_R and I_VCNT <= 255 and star_dis = '0' then
		
			-- generate a star ? --
			if I_PIX(0) = '0' then
			
				if star_rng(16 downto 14) = "011" and (star_rng(7 downto 0) = x"B7" or star_rng(7 downto 0) = x"D7" or star_rng(7 downto 0) = x"BB" or star_rng(7 downto 0) = x"DB") then
				
					-- star detected - colour = star_rng(13 downto 8) modified by some outputs
					
					-- CONT R       Changes contrast of the red/green/blue part of the stars. This is used to make the starfield flicker
					-- CONT G
					-- CONT B
					
					-- ALRD         Turns background red on (Space Firebird only)
					-- ALBU         Turns background blue on (Space Firebird only)
					
					colour := (star_rng(13) or (ALRD and I_Firebird)) & (star_rng(12) and I_CONT_R) & (star_rng(11) or (ALBU and I_Firebird)) & (star_rng(10) and I_CONT_B) & star_rng(9) & (star_rng(8) and I_CONT_G);
					
				else
				
					-- back ground controls only
					colour := (ALRD and I_Firebird) & '0' & (ALBU and I_Firebird) & "000";
					
				end if;
				
				RED   := 72 * to_integer(unsigned(colour(5 downto 4)));
				BLUE  := 72 * to_integer(unsigned(colour(3 downto 2)));
				GREEN := 72 * to_integer(unsigned(colour(1 downto 0)));

				-- next RNG (skip one if Space Firebird)
				if I_VCNT = 255 and skipstar = '1' then
					skipstar <= '0';
				else
					star_rng <= star_rng(15 downto 0) & (star_rng(16) xor star_rng(4));
				end if;
				
			else
			
				-- Output on 1
				SR <= std_logic_vector(to_unsigned(RED, 8));
				SG <= std_logic_vector(to_unsigned(GREEN, 8));
				SB <= std_logic_vector(to_unsigned(BLUE, 8));
				
			end if;
					
		else	
		
			-- no stars or background
			
			SR <= "00000000";
			SG <= "00000000";
			SB <= "00000000";
			
		end if;

  end	process;
  
end architecture;
