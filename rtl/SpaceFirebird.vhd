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

entity SPACEFIREBIRD is
port
(
	I_Firebird : in  std_logic;
	I_Bullet   : in  std_logic;
	I_Song     : in  std_logic;
	
	O_VIDEO_R  : out std_logic_vector(7 downto 0);
	O_VIDEO_G  : out std_logic_vector(7 downto 0);
	O_VIDEO_B  : out std_logic_vector(7 downto 0);
	--
	I_HCOUNT   : in  std_logic_vector(8 downto 0);
	I_VCOUNT   : in  std_logic_vector(8 downto 0);
	--
	SAMPLE_CTL : out std_logic_vector(5 downto 0);
	O_AUDIO    : out std_logic_vector(15 downto 0);
	--
	dipsw1     : in  std_logic_vector(7 downto 0);
	in0        : in  std_logic_vector(7 downto 0);
	in1        : in  std_logic_vector(7 downto 0);
	in2        : in  std_logic_vector(7 downto 0);
	--
	dn_addr    : in  std_logic_vector(15 downto 0);
	dn_data    : in  std_logic_vector(7 downto 0);
	dn_wr      : in  std_logic;
	dn_ld	     : in  std_logic;
	--
	PCADDR     : out std_logic_vector(15 downto 0);
	PCDATA     : out std_logic_vector(7 downto 0);
	--
	RESET      : in  std_logic;
	O_FLIP     : out std_logic;
	--
	I_PIX      : in  std_logic_vector(1 downto 0);
	CPU_CLK    : in  std_logic;
	VID_CLK    : in  std_logic;
	SND_CLK    : in  std_logic;
	SYS_CLK    : in  std_logic
);
end;

architecture RTL of SPACEFIREBIRD is

	COMPONENT NintendoSoundboard PORT (
		W_CLK_24576M 	: in  std_logic;
		W_RESETn  		: in  std_logic;
		I_SOUND_CNT  	: in  std_logic_vector(4 downto 0);
		O_SOUND_DAT   	: out std_logic_vector(15 downto 0);
		ROM_A    		: out std_logic_vector(10 downto 0);
		ROM_D    		: in  std_logic_vector(7 downto 0)
	);
	END COMPONENT;


	signal R,G,B				: std_logic_vector(7 downto 0);
	
	-- cpu
	signal cpu_m1_l         : std_logic;
	signal cpu_mreq_l       : std_logic;
	signal cpu_iorq_l       : std_logic;
	signal cpu_rd_l         : std_logic;
	signal cpu_wr_l         : std_logic;
	signal cpu_rfsh_l       : std_logic;
	signal cpu_int_l        : std_logic;
	signal cpu_addr         : std_logic_vector(15 downto 0);
	signal cpu_data_out     : std_logic_vector(7 downto 0);
	signal cpu_data_in      : std_logic_vector(7 downto 0) := "00000000";

	-- Memory mapping
	signal rom_ld           : std_logic := '0';
	signal rom_rd           : std_logic := '0';
	signal ram_rd           : std_logic := '0';
	signal vid_rd0          : std_logic := '0';
	signal vid_rd1          : std_logic := '0';
	signal vid_rd2          : std_logic := '0';
	signal vid_rd3          : std_logic := '0';
	signal sound_rom_ld     : std_logic := '0';
	signal intvec           : std_logic := '0';
	
	signal ram_wr           : std_logic := '0';
	signal vid_wr0          : std_logic := '0';
	signal vid_wr1          : std_logic := '0';
	signal vid_wr2          : std_logic := '0';
	signal vid_wr3          : std_logic := '0';
	
	signal IO_rd 				: std_logic := '0';
	signal IO_wr 				: std_logic := '0';
	
	signal rom_data         : std_logic_vector(7 downto 0);
	signal ram_data         : std_logic_vector(7 downto 0);
	signal vid_data0        : std_logic_vector(7 downto 0);
	signal vid_data1        : std_logic_vector(7 downto 0);
	signal vid_data2        : std_logic_vector(7 downto 0);
	signal vid_data3        : std_logic_vector(7 downto 0);
	signal col_data         : std_logic_vector(3 downto 0);
	signal IO_Data 			: std_logic_vector(7 downto 0);
	signal sound_rom_data	: std_logic_vector(7 downto 0);
	
	signal bus_ad           : std_logic_vector(15 downto 0);
	signal snd_bus_ad       : std_logic_vector(9 downto 0);
	signal ROM_A            : std_logic_vector(10 downto 0);
	signal ROM_D            : std_logic_vector(7 downto 0);
	
	signal Global_Reset     : std_logic;
	signal r_int_fb_current : std_logic_vector(7 downto 0);

	-- Video
	signal vid_addr         : std_logic_vector(6 downto 0);
	signal v_sprite_data    : std_logic_vector(31 downto 0);
	signal v_colour_data	   : std_logic_vector(3 downto 0);
	signal RV      			: std_logic := '0';
	signal VREF      			: std_logic := '0';
	signal CREF      			: std_logic := '0';
	signal CONT_R    			: std_logic := '0';
	signal CONT_G    			: std_logic := '0';
	signal CONT_B    			: std_logic := '0';
	signal ALRD      			: std_logic := '0';
	signal ALBU      			: std_logic := '0';
	signal ALBA      			: std_logic := '0';
	signal pixel_sync			: std_logic;

	-- Sound
	signal SFX 			   	: std_logic_vector(15 downto 0);
	signal S_Control			: std_logic_vector(7 downto 0) := x"00";
	signal S_Trigger			: std_logic_vector(5 downto 0);
	signal L_Trigger			: std_logic_vector(3 downto 0);
	
begin

  O_VIDEO_R <= R;
  O_VIDEO_G <= G;
  O_VIDEO_B <= B;
  O_FLIP    <= RV;
  O_AUDIO   <= SFX;
  
  SAMPLE_CTL <= S_Trigger;
  PCADDR    <= cpu_addr;
  PCDATA    <= rom_data;
  
  Global_Reset <= (not RESET);  

  p_cpu_int : process
  begin
   wait until rising_edge(VID_CLK);

	-- Interrupt Acknowledge
	if (intvec = '1') then
	  cpu_int_l <= '1';
	end if;
	
	if I_HCOUNT = 260 then
	  cpu_int_l <= '1';
	  if I_VCOUNT = "011110000" then 	 	-- F0 
			cpu_int_l <= '0';
			r_int_fb_current <= x"D7";	 		-- RST 2
	  elsif I_VCOUNT = "010000000" then 	-- 80 
			cpu_int_l <= '0';
			r_int_fb_current <= x"CF";	 		-- RST 1
	  end if;
	end if;

 end process;

--
-- cpu
--
	cpu : entity work.T80as
	port map (
		RESET_n       => Global_Reset,
		CLK_n         => CPU_CLK,
		ENA           => '1',
		WAIT_n        => '1',
		INT_n         => cpu_int_l,
		NMI_n         => '1',
		BUSRQ_n       => '1',
		MREQ_n        => cpu_mreq_l,
		RD_n          => cpu_rd_l,
		WR_n          => cpu_wr_l,
		RFSH_n        => cpu_rfsh_l,
		A             => cpu_addr,
		DI            => cpu_data_in,
		DO            => cpu_data_out,
		M1_n          => cpu_m1_l,
		IORQ_n        => cpu_iorq_l,
		HALT_n        => open,
		BUSAK_n       => open,
		DOE           => open
	);

--
-- address decode
--
--
--    0000-3FFF ROM       Code
--    8000-83FF RAM       Sprite RAM
--    C000-C7FF RAM       Game RAM

rom_ld <= '1' when dn_addr(15 downto 14)  = "00" and dn_ld='1' else '0';
bus_ad <= dn_addr(15 downto 0) when dn_ld='1' else cpu_addr;

p_mem_decode : process(cpu_addr,cpu_iorq_l,cpu_rd_l,cpu_wr_l,cpu_mreq_l,cpu_m1_l,cpu_rfsh_l)
variable address : natural range 0 to 2**16 - 1;
begin
	rom_rd  <= '0';
	ram_rd  <= '0';
	vid_rd0 <= '0';
	vid_rd1 <= '0';
	vid_rd2 <= '0';
	vid_rd3 <= '0';
	io_rd   <= '0';

	ram_wr <= '0';
	vid_wr0 <= '0';
	vid_wr1 <= '0';
	vid_wr2 <= '0';
	vid_wr3 <= '0';
	io_wr  <= '0';

	-- interrupt ack
	intvec <= not cpu_iorq_l and not cpu_m1_l; 
	
	address := to_integer(unsigned(cpu_addr));
	
	-- Ram/Rom read or write
	if cpu_mreq_l='0' and cpu_rfsh_l = '1' then
		if cpu_rd_l='0' then
			case address is
				when 16#0000# to 16#3FFF# => rom_rd <= '1';
				when 16#8000# to 16#80FF# => vid_rd0 <= '1';
				when 16#8100# to 16#81FF# => vid_rd1 <= '1';
				when 16#8200# to 16#82FF# => vid_rd2 <= '1';
				when 16#8300# to 16#83FF# => vid_rd3 <= '1';
				when 16#C000# to 16#C7FF# => ram_rd <= '1';
				when others => null;
			end case;
		elsif cpu_wr_l='0' then
			case address is
				when 16#8000# to 16#80FF# => vid_wr0 <= '1';
				when 16#8100# to 16#81FF# => vid_wr1 <= '1';
				when 16#8200# to 16#82FF# => vid_wr2 <= '1';
				when 16#8300# to 16#83FF# => vid_wr3 <= '1';
				when 16#C000# to 16#C7FF# => ram_wr <= '1';
				when others => null;
			end case;
		end if;
	elsif cpu_iorq_l='0' then
		if cpu_addr(7 downto 4)="0000" and cpu_m1_l='1' then
			io_rd <= not cpu_rd_l;
			io_wr <= not cpu_wr_l;
		end if;
	end if;

end process;

 -- Mux back to CPU
 p_cpu_src_data_mux : process(IO_Data,rom_data,ram_data,vid_data0,vid_data1,vid_data2,vid_data3,col_data,io_rd,rom_rd,ram_rd,vid_rd0,vid_rd1,vid_rd2,vid_rd3,intvec,r_int_fb_current)
 begin
	 if intvec  = '1' then
		cpu_data_in <= r_int_fb_current;
	 elsif io_rd = '1' then
		cpu_data_in <= IO_Data;
	 elsif rom_rd = '1' then
		cpu_data_in <= rom_data;
	 elsif ram_rd = '1' then
		cpu_data_in <= ram_data;
	 elsif vid_rd0 = '1' then
		cpu_data_in <= vid_data0;
	 elsif vid_rd1 = '1' then
		cpu_data_in <= vid_data1;
	 elsif vid_rd2 = '1' then
		cpu_data_in <= vid_data2;
	 elsif vid_rd3 = '1' then
		cpu_data_in <= vid_data3;
	 else 
	   cpu_data_in <= x"FF";
 	 end if;
 end process;
					
 -- rom : 0000-3FFF
 
 program_rom : entity work.spram
	generic map (
	  addr_width => 14
	)
	port map (
	  q        => rom_data,
	  data     => dn_data(7 downto 0),
	  address  => bus_ad(13 downto 0),
	  wren     => dn_wr and rom_ld,
	  clock    => SYS_CLK
   );

 -- ram : C000-C7FF
 
 program_ram : entity work.spram
	generic map (
	  addr_width => 11
	)
	port map (
	  q        => ram_data,
	  data     => cpu_data_out,
	  address  => cpu_addr(10 downto 0),
	  wren     => ram_wr,
	  clock    => SYS_CLK
   );


 -- video ram : 8000-83FF - 4 banks so we can access all on same clock cycle (hardware uses 8 ram chips)
 
vram00 : entity work.dpram_difc
	 generic map (
	  addr_width_a => 8,
	  addr_width_b => 8
	 )
	 port map (
	  q_a        => vid_data0,
	  data_a     => cpu_data_out,
	  address_a  => cpu_addr(7 downto 0),
	  wren_a     => vid_wr0,
	  enable_a   => vid_rd0 or vid_wr0,
	  clock_a    => SYS_CLK,
	  
	  address_b  => VREF & vid_addr(6 downto 0),
	  q_b        => v_sprite_data(7 downto 0),
	  clock_b    => VID_CLK
	 );

vram01 : entity work.dpram_difc
	 generic map (
	  addr_width_a => 8,
	  addr_width_b => 8
	 )
	 port map (
	  q_a        => vid_data1,
	  data_a     => cpu_data_out,
	  address_a  => cpu_addr(7 downto 0),
	  wren_a     => vid_wr1,
	  enable_a   => vid_rd1 or vid_wr1,
	  clock_a    => SYS_CLK,
	  
	  address_b  => VREF & vid_addr(6 downto 0),
	  q_b        => v_sprite_data(15 downto 8),
	  clock_b    => VID_CLK
	 );

vram10 : entity work.dpram_difc
	 generic map (
	  addr_width_a => 8,
	  addr_width_b => 8
	 )
	 port map (
	  q_a        => vid_data2,
	  data_a     => cpu_data_out,
	  address_a  => cpu_addr(7 downto 0),
	  wren_a     => vid_wr2,
	  enable_a   => vid_rd2 or vid_wr2,
	  clock_a    => SYS_CLK,
	  
	  address_b  => VREF & vid_addr(6 downto 0),
	  q_b        => v_sprite_data(23 downto 16),
	  clock_b    => VID_CLK
	 );

vram11 : entity work.dpram_difc
	 generic map (
	  addr_width_a => 8,
	  addr_width_b => 8
	 )
	 port map (
	  q_a        => vid_data3,
	  data_a     => cpu_data_out,
	  address_a  => cpu_addr(7 downto 0),
	  wren_a     => vid_wr3,
	  enable_a   => vid_rd3 or vid_wr3,
	  clock_a    => SYS_CLK,
	  
	  address_b  => VREF & vid_addr(6 downto 0),
	  q_b        => v_sprite_data(31 downto 24),
	  clock_b    => VID_CLK
	 );
	 
---
--- IO
---

-- Register Write

--   Port 0 - Video
--
--       bit 0 = Screen flip. (RV)
--       bit 5 = Char/Sprite Bank switch (VREF)
--       bit 6 = Turns on Bit 2 of the color PROM. Used to change the bird colors. (CREF)
--
--   Port 1
--       bit 0 = discrete sound (Enemy death)
--       bit 1 = INT to 8035
--       bit 2 = T1 input to 8035
--       bit 3 = PB4 input to 8035
--       bit 4 = PB5 input to 8035
--       bit 5 = T0 input to 8035
--       bit 6 = discrete sound (Ship fire)
--       bit 7 = discrete sound (Explosion noise)
--
--   Port 2 - Video control
--
--      These are passed to the sound board and are used to produce a
--      red flash effect when you die.
--
--      bit 0 = CONT R       Changes contrast of the red/green/blue part of the stars. This is used to make the starfield flicker
--      bit 1 = CONT G
--      bit 2 = CONT B
--      bit 3 = ALRD         Turns background red on
--      bit 4 = ALBU         Turns background blue on
--      bit 7 = ALBA         Turns off star field (no star field)
		
IO_Write : Process
begin
	wait until rising_edge(CPU_CLK);
	
	if Global_Reset='0' then
			-- Reset ports
			RV	  		 <= '0';	
			VREF 		 <= '0';
			CREF 		 <= '0';
			CONT_R    <= '0';
			CONT_G    <= '0';
			CONT_B    <= '0';
			ALRD      <= '0';
			ALBU      <= '0';
			ALBA      <= '0';
			S_Control <= "00000000";
	end if;
	
	if io_wr='1' then
		  case cpu_addr(3 downto 0) is
			 when x"0" =>
						-- Video
						RV   <= cpu_data_out(0);
						VREF <= cpu_data_out(5);
						CREF <= cpu_data_out(6);
			 when x"1" => 
						-- Sound
						S_Control <= cpu_data_out;
			 when x"2" =>
						-- Stars
						CONT_R <= cpu_data_out(0);
						CONT_G <= cpu_data_out(1);
						CONT_B <= cpu_data_out(2);
						ALRD   <= cpu_data_out(3);
						ALBU   <= cpu_data_out(4);
						ALBA   <= cpu_data_out(7);
			 when others => null;
		  end case;
	end if;
end process;

-- register read

--    Port 0
--
--       bit 0 = Player 1 Right
--       bit 1 = Player 1 Left
--       bit 4 = Player 1 Warp / Escape
--       bit 7 = Player 1 Fire
--
--    Port 1
--
--       bit 0 = Player 2 Right
--       bit 1 = Player 2 Left
--       bit 4 = Player 2 Warp / Escape
--       bit 7 = Player 2 Fire
--
--    Port 2
--
--       bit 2 = Start 1 Player game
--       bit 3 = Start 2 Players game
--       bit 6 = Test switch
--       bit 7 = Coin and Service switch
--
--    Port 3
--
--       bit 0 = Dipswitch 1
--       bit 1 = Dipswitch 2
--       bit 2 = Dipswitch 3
--       bit 3 = Dipswitch 4
--       bit 4 = Dipswitch 5
--       bit 5 = Dipswitch 6
		 
		 
IO_Read : Process
begin
	wait until rising_edge(CPU_CLK);

	if IO_rd = '1' then
		  case cpu_addr(1 downto 0) is
			 when "00" => 
				IO_Data <= in0;
			 when "01" => 
				IO_Data <= in1;
			 when "10" =>
				IO_Data <= in2;
			 when "11" => 
				IO_Data <= dipsw1;
		  end case;
	end if;
end process;
	 
--
-- video subsystem
--
video : work.SPACEFIREBIRD_VIDEO
port map (
	I_Firebird => I_Firebird,
	I_Bullet  => I_Bullet,
	--
	I_HCNT    => I_HCOUNT,
	I_VCNT    => I_VCOUNT,
	--
	I_FLIP    => RV,
	I_CREF    => CREF,
	I_STARS   => ALBA,
	I_CONT_R  => CONT_R,
	I_CONT_G  => CONT_G,
	I_CONT_B  => CONT_B,
	I_ALRD    => ALRD,
	I_ALBU    => ALBU,
	--
	I_SPRITE  => v_sprite_data,
	O_VADDR   => vid_addr,
	--
	dn_addr   => dn_addr,
	dn_data   => dn_data,
	dn_wr     => dn_wr,
	dn_ld     => dn_ld,
	--
	O_RED     => R,
	O_GREEN   => G,
	O_BLUE    => B,
	--
	RESET     => RESET,
	I_PIX     => I_PIX,
	VID_CLK   => VID_CLK,
	SYS_CLK   => SYS_CLK
);

--
-- audio subsystem
--

SampleControl : Process
begin
	wait until rising_edge(CPU_CLK);
	
	if Global_Reset='0' then
	
		-- All stop
		S_Trigger <= "000000";
		L_Trigger <= "0000";
		
	else
	
		-- Save Last for transition tests
		L_Trigger <= ALBU & S_Control(0) & S_Control(6) & S_Control(7);
		
		-- bit 0 = discrete sound (Enemy death)
		if L_Trigger(2) /= S_Control(0) then
			S_Trigger(0) <= not S_Control(0);
		end if;

		-- bit 7 = discrete sound (Explosion noise)
		if L_Trigger(0) /= S_Control(7) then
			S_Trigger(1) <= not S_Control(7);	-- looped sample
			S_Trigger(2) <= S_Control(7);			-- decay sample
		end if;
		
		-- bit 6 = discrete sound (Ship fire)
		if L_Trigger(1) /= S_Control(6) then
			S_Trigger(3) <= not S_Control(6);
		end if;
		
		if I_Firebird='1' or I_Song='1' then
			S_Trigger (5 downto 4) <= "00";
		else
			-- Space Demon - assume tune selected by ALRD - without access to PCB cannot confirm!
			if L_Trigger(3) /= ALBU then
				if ALRD='1' then
					S_Trigger(5 downto 4) <= '0' & ALBU;
				else
					S_Trigger(5 downto 4) <= ALBU & '0';
				end if;
			end if;
		end if;
		
	end if;
	
end process;

-- Tone generator

sound_rom_ld  <= '1' when dn_addr(15 downto 11)  = "01011" and dn_ld='1' else '0';
snd_bus_ad <= dn_addr(9 downto 0) when dn_ld='1' else ROM_A(9 downto 0);
	
sound_rom : entity work.spram
	generic map (
	  addr_width => 10
	)
	port map (
	  q        => ROM_D,
	  data     => dn_data(7 downto 0),
	  address  => snd_bus_ad,
	  wren     => dn_wr and sound_rom_ld,
	  clock    => SYS_CLK
   );

audio : NintendoSoundboard
port map (
	W_CLK_24576M	=> SND_CLK,
	W_RESETn			=> Global_Reset,
	I_SOUND_CNT		=> S_Control(5 downto 1),
	O_SOUND_DAT		=> SFX,
	ROM_A				=> ROM_A,
	ROM_D				=> ROM_D
);

end RTL;
