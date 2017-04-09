library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

-- This is the top level
-- The video in https://www.youtube.com/watch?v=g_1HyxBzjl0 gives a 
-- high level view of the computer.

entity bcomp is

   generic (
       FREQ       : integer := 25000000 -- Input clock frequency
       );
   port (
      -- Clock
      clk_i       : in  std_logic;  -- 25 MHz

      -- Input switches
      sw_i        : in  std_logic_vector (7 downto 0);

      -- Inputs from PMOD's
      pmod_i      : in  std_logic_vector (15 downto 0);

      -- Input buttons
      btn_i       : in  std_logic_vector (3 downto 0);

      -- Output LEDs
      led_o       : out std_logic_vector (7 downto 0);

      -- pragma synthesis_off
      -- Used during testing
      databus_i       : in  std_logic_vector (7 downto 0);
      control_i       : in  std_logic_vector (14 downto 0);
      -- pragma synthesis_on

      -- Output segment display
      seg_ca_o    : out std_logic_vector (6 downto 0);
      seg_dp_o    : out std_logic;
      seg_an_o    : out std_logic_vector (3 downto 0)

      );

end bcomp;

architecture Structural of bcomp is

    -- The main internal clock
    signal clk  : std_logic;

    -- The main data bus
    -- All the blocks connected to the data bus
    -- must have an enable_i pin telling the block,
    -- whether to output data to the bus or not.
    -- Additionally, all these blocks provide
    -- access to the data before the output buffer.
    -- These blocks are: 
    --   A-register
    --   B-register
    --   instruction register
    --   ALU
    --   RAM
    --   Program counter
    signal databus       : std_logic_vector(7 downto 0);

    -- Interpretation of input button and switches.
    alias clk_button     : std_logic is btn_i(0);
    alias write_btn      : std_logic is btn_i(1);
    alias reset_btn      : std_logic is btn_i(2);

    alias clk_switch     : std_logic is sw_i(0);
    alias runmode        : std_logic is sw_i(1);
    alias address_sw     : std_logic_vector (3 downto 0) is pmod_i(11 downto 8);
    alias data_sw        : std_logic_vector (7 downto 0) is pmod_i( 7 downto 0);

    alias led_select     : std_logic_vector (1 downto 0) is sw_i(3 downto 2);
    constant LED_SELECT_BUS  : std_logic_vector (1 downto 0) := "00";
    constant LED_SELECT_ALU  : std_logic_vector (1 downto 0) := "01";
    constant LED_SELECT_RAM  : std_logic_vector (1 downto 0) := "10";
    constant LED_SELECT_ADDR : std_logic_vector (1 downto 0) := "11";

    -- Communication between blocks
    signal areg_value    : std_logic_vector (7 downto 0);
    signal breg_value    : std_logic_vector (7 downto 0);
    signal ireg_value    : std_logic_vector (7 downto 0);
    signal address_value : std_logic_vector (3 downto 0);
    signal disp_two_comp : std_logic;
    signal disp_value    : std_logic_vector (7 downto 0);

    -- Debug outputs connected to LEDs
    signal alu_value     : std_logic_vector (7 downto 0);
    signal ram_value     : std_logic_vector (7 downto 0);
    signal pc_value      : std_logic_vector (3 downto 0);

    -- Control signals
    signal control    : std_logic_vector (14 downto 0);
    alias  control_AI : std_logic is control(0);  -- A register load
    alias  control_AO : std_logic is control(1);  -- A register output enable
    alias  control_BI : std_logic is control(2);  -- B register load
    alias  control_BO : std_logic is control(3);  -- B register output enable
    alias  control_II : std_logic is control(4);  -- Instruction register load
    alias  control_IO : std_logic is control(5);  -- Instruction register output enable
    alias  control_EO : std_logic is control(6);  -- ALU output enable
    alias  control_SU : std_logic is control(7);  -- ALU subtract
    alias  control_MI : std_logic is control(8);  -- Memory address register load
    alias  control_RI : std_logic is control(9);  -- RAM load (write)
    alias  control_RO : std_logic is control(10); -- RAM output enable
    alias  control_CO : std_logic is control(11); -- Program counter output enable
    alias  control_J  : std_logic is control(12); -- Program counter jump
    alias  control_CE : std_logic is control(13); -- Program counter count enable
    alias  control_OI : std_logic is control(14); -- Program counter count enable

begin

    -- pragma synthesis_off
    databus <= databus_i;
    control <= control_i;
    -- pragma synthesis_on

    led_o <= databus                when led_select = LED_SELECT_BUS else
             alu_value              when led_select = LED_SELECT_ALU else
             ram_value              when led_select = LED_SELECT_RAM else
             "0000" & address_value when led_select = LED_SELECT_ADDR;

    -- Instantiate clock module
    inst_clock_logic : entity work.clock_logic
    port map (
                 clk_i       => clk_i      , -- External crystal
                 sw_i        => clk_switch ,
                 btn_i       => clk_button ,
                 hlt_i       => '0'        ,
                 clk_deriv_o => clk         -- Main internal clock
             );

    -- Instantiate A-register
    inst_a_register : entity work.register_8bit
    port map (
                 clk_i       => clk          ,
                 load_i      => control_AI   ,
                 enable_i    => control_AO   ,
                 clr_i       => reset_btn    ,
                 data_io     => databus      ,
                 reg_o       => areg_value     -- to ALU
             );

    -- Instantiate B-register
    inst_b_register : entity work.register_8bit
    port map (
                 clk_i       => clk          ,
                 load_i      => control_BI   ,
                 enable_i    => control_BO   ,
                 clr_i       => reset_btn    ,
                 data_io     => databus      ,
                 reg_o       => breg_value     -- to ALU
             );

    -- Instantiate instruction register
    inst_instruction_register : entity work.register_8bit
    port map (
                 clk_i       => clk          ,
                 load_i      => control_II   ,
                 enable_i    => control_IO   ,
                 clr_i       => reset_btn    ,
                 data_io     => databus      ,
                 reg_o       => ireg_value     -- to instruction decoder
             );

    -- Instantiate ALU
    inst_alu : entity work.alu
    port map (
                 sub_i       => control_SU ,
                 enable_i    => control_EO ,
                 areg_i      => areg_value ,
                 breg_i      => breg_value ,
                 result_o    => databus    ,
                 led_o       => alu_value    -- Debug output
             );

    -- Instantiate memory address register
    inst_memory_address_register : entity work.memory_address_register
    port map (
                 clk_i       => clk                 ,
                 load_i      => control_MI          ,
                 address_i   => databus(3 downto 0) ,
                 runmode_i   => runmode             ,
                 sw_i        => address_sw          ,
                 address_o   => address_value         -- to RAM module
             );

    -- Instantiate RAM module
    inst_ram_module : entity work.ram_module
    port map (
                 clk_i       => clk           ,
                 wr_i        => control_RI    ,
                 enable_i    => control_RO    ,
                 data_io     => databus       ,
                 address_i   => address_value ,
                 runmode_i   => runmode       ,
                 sw_data_i   => data_sw       ,
                 wr_button_i => write_btn     ,
                 data_led_o  => ram_value       -- Debug output
             );

    -- Instantiate Program counter
    inst_program_counter : entity work.program_counter
    port map (
                 clk_i       => clk                 ,
                 clr_i       => reset_btn           ,
                 data_io     => databus(3 downto 0) ,
                 load_i      => control_J           ,
                 enable_i    => control_CO          ,
                 count_i     => control_CE          ,
                 led_o       => pc_value              -- Debug output
             );

    -- Instantiate Display
    inst_display : entity work.display
    port map (
                 clk_i       => clk_i         , -- Use crystal clock
                 two_comp_i  => disp_two_comp ,
                 value_i     => disp_value    ,
                 seg_ca_o    => seg_ca_o      ,
                 seg_dp_o    => seg_dp_o      ,
                 seg_an_o    => seg_an_o 
             );

    -- Instantiate output register
    inst_output_register : entity work.output_register
    port map (
                 clk_i       => clk        ,
                 clr_i       => reset_btn  ,
                 data_i      => databus    ,
                 load_i      => control_OI ,
                 reg_o       => disp_value  -- Connected to display module
             );

end Structural;

