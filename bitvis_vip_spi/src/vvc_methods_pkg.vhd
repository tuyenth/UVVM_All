--========================================================================================================================
-- Copyright (c) 2017 by Bitvis AS.  All rights reserved.
-- You should have received a copy of the license file containing the MIT License (see LICENSE.TXT), if not, 
-- contact Bitvis AS <support@bitvis.no>.
--
-- UVVM AND ANY PART THEREOF ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
-- WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS
-- OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
-- OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH UVVM OR THE USE OR OTHER DEALINGS IN UVVM.
--========================================================================================================================

------------------------------------------------------------------------------------------
-- Description   : See library quick reference (under 'doc') and README-file(s)
------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

use work.spi_bfm_pkg.all;
use work.vvc_cmd_pkg.all;
use work.td_vvc_framework_common_methods_pkg.all;
use work.td_target_support_pkg.all;


--=================================================================================================
--=================================================================================================
--=================================================================================================
package vvc_methods_pkg is

  --===============================================================================================
  -- Types and constants for the SPI VVC 
  --===============================================================================================
  constant C_VVC_NAME     : string := "SPI_VVC";

  signal SPI_VVCT          : t_vvc_target_record := set_vvc_target_defaults(C_VVC_NAME);
  alias  THIS_VVCT         : t_vvc_target_record is SPI_VVCT;
  alias  t_bfm_config is t_spi_bfm_config;

  constant C_SPI_INTER_BFM_DELAY_DEFAULT : t_inter_bfm_delay := (
    delay_type                          => NO_DELAY,
    delay_in_time                       => 0 ns,
    inter_bfm_delay_violation_severity  => WARNING
  );

  type t_vvc_config is
  record
    inter_bfm_delay                       : t_inter_bfm_delay;  -- Minimum delay between BFM accesses from the VVC. If parameter delay_type is set to NO_DELAY, BFM accesses will be back to back, i.e. no delay.
    cmd_queue_count_max                   : natural;            -- Maximum pending number in command queue before queue is full. Adding additional commands will result in an ERROR.
    cmd_queue_count_threshold             : natural;            -- An alert with severity 'cmd_queue_count_threshold_severity' will be issued if command queue exceeds this count. Used for early warning if command queue is almost full. Will be ignored if set to 0.
    cmd_queue_count_threshold_severity    : t_alert_level;      -- Severity of alert to be initiated if exceeding cmd_queue_count_threshold
    result_queue_count_max                : natural;           -- Maximum number of unfetched results before result_queue is full. 
    result_queue_count_threshold_severity : t_alert_level;     -- An alert with severity 'result_queue_count_threshold_severity' will be issued if command queue exceeds this count. Used for early warning if result queue is almost full. Will be ignored if set to 0.
    result_queue_count_threshold          : natural;           -- Severity of alert to be initiated if exceeding result_queue_count_threshold
    bfm_config                            : t_spi_bfm_config;   -- Configuration for the BFM. See BFM quick reference 
    msg_id_panel                          : t_msg_id_panel;     -- VVC dedicated message ID panel
  end record;

  type t_vvc_config_array is array (natural range <>) of t_vvc_config;

  constant C_SPI_VVC_CONFIG_DEFAULT : t_vvc_config := (
    inter_bfm_delay                       => C_SPI_INTER_BFM_DELAY_DEFAULT,
    cmd_queue_count_max                   => C_CMD_QUEUE_COUNT_MAX,
    cmd_queue_count_threshold_severity    => C_CMD_QUEUE_COUNT_THRESHOLD_SEVERITY,
    cmd_queue_count_threshold             => C_CMD_QUEUE_COUNT_THRESHOLD,
    result_queue_count_max                => C_RESULT_QUEUE_COUNT_MAX,
    result_queue_count_threshold_severity => C_RESULT_QUEUE_COUNT_THRESHOLD_SEVERITY,
    result_queue_count_threshold          => C_RESULT_QUEUE_COUNT_THRESHOLD,
    bfm_config                            => C_SPI_BFM_CONFIG_DEFAULT,
    msg_id_panel                          => C_VVC_MSG_ID_PANEL_DEFAULT
  );

  type t_vvc_status is
  record
    current_cmd_idx       : natural;
    previous_cmd_idx      : natural;
    pending_cmd_cnt       : natural;
  end record;

  type t_vvc_status_array is array (natural range <>) of t_vvc_status;

  constant C_VVC_STATUS_DEFAULT : t_vvc_status := (
    current_cmd_idx      => 0,
    previous_cmd_idx     => 0,
    pending_cmd_cnt      => 0
  );

  -- Transaction information for the wave view during simulation
  type t_transaction_info is
  record
    operation       : t_operation;
    msg             : string(1 to C_VVC_CMD_STRING_MAX_LENGTH);
    tx_data         : std_logic_vector(C_VVC_CMD_DATA_MAX_LENGTH-1 downto 0);
    rx_data         : std_logic_vector(C_VVC_CMD_DATA_MAX_LENGTH-1 downto 0);
    data_exp        : std_logic_vector(C_VVC_CMD_DATA_MAX_LENGTH-1 downto 0);
  end record;

  type t_transaction_info_array is array (natural range <>) of t_transaction_info;

  constant C_TRANSACTION_INFO_DEFAULT : t_transaction_info := (
    tx_data                => (others => '0'),
    rx_data                => (others => '0'),
    data_exp               => (others => '0'),
    operation              =>  NO_OPERATION,
    msg                    => (others => ' ')
  );
    

  shared variable shared_spi_vvc_config : t_vvc_config_array(0 to C_MAX_VVC_INSTANCE_NUM) := (others => C_SPI_VVC_CONFIG_DEFAULT);
  shared variable shared_spi_vvc_status : t_vvc_status_array(0 to C_MAX_VVC_INSTANCE_NUM) := (others => C_VVC_STATUS_DEFAULT);
  shared variable shared_spi_transaction_info : t_transaction_info_array(0 to C_MAX_VVC_INSTANCE_NUM) := (others => C_TRANSACTION_INFO_DEFAULT);

  --==============================================================================
  -- Methods dedicated to this VVC
  -- - These procedures are called from the testbench in order to queue BFM calls 
  --   in the VVC command queue. The VVC will store and forward these calls to the 
  --   SPI BFM when the command is at the from of the VVC command queue. 
  -- - For details on how the BFM procedures work, see spi_bfm_pkg.vhd or the 
  --   quickref.
  --==============================================================================

  ----------------------------------------------------------
  -- SPI_MASTER
  ----------------------------------------------------------
  procedure spi_master_transmit_and_receive(
    signal   VVCT               : inout t_vvc_target_record;
    constant vvc_instance_idx   : in integer;
    constant data               : in std_logic_vector;
    constant msg                : in string
  );

  procedure spi_master_transmit_and_check(
    signal   VVCT               : inout t_vvc_target_record;
    constant vvc_instance_idx   : in integer;
    constant data               : in std_logic_vector;    
    constant data_exp           : in std_logic_vector;
    constant msg                : in string;
    constant alert_level        : in t_alert_level := ERROR
  );

  procedure spi_master_transmit_only(
    signal   VVCT               : inout t_vvc_target_record;
    constant vvc_instance_idx   : in integer;
    constant data               : in std_logic_vector;
    constant msg                : in string
  );
  
  procedure spi_master_receive_only(
    signal   VVCT               : inout t_vvc_target_record;
    constant vvc_instance_idx   : in integer;
    constant msg                : in string
  );
  
  procedure spi_master_check_only(
    signal   VVCT               : inout t_vvc_target_record;
    constant vvc_instance_idx   : in integer;
    constant data_exp           : in std_logic_vector;
    constant msg                : in string;
    constant alert_level        : in t_alert_level := ERROR
  );
   
  ----------------------------------------------------------
  -- SPI_SLAVE
  ----------------------------------------------------------   
  procedure spi_slave_transmit_and_receive(
    signal   VVCT               : inout t_vvc_target_record;
    constant vvc_instance_idx   : in integer;
    constant data               : in std_logic_vector;
    constant msg                : in string
  );

  procedure spi_slave_transmit_and_check(
    signal   VVCT               : inout t_vvc_target_record;
    constant vvc_instance_idx   : in integer;
    constant data               : in std_logic_vector;
    constant data_exp           : in std_logic_vector;
    constant msg                : in string;
    constant alert_level        : in t_alert_level := ERROR    
    );

  procedure spi_slave_transmit_only(
    signal   VVCT               : inout t_vvc_target_record;
    constant vvc_instance_idx   : in integer;
    constant data               : in std_logic_vector;
    constant msg                : in string
  );

  procedure spi_slave_receive_only(
    signal   VVCT               : inout t_vvc_target_record;
    constant vvc_instance_idx   : in integer;
    constant msg                : in string
  );

  procedure spi_slave_check_only(
    signal   VVCT               : inout t_vvc_target_record;
    constant vvc_instance_idx   : in integer;
    constant data               : in std_logic_vector;
    constant msg                : in string;
    constant alert_level        : in t_alert_level := ERROR
  );


end package vvc_methods_pkg;

package body vvc_methods_pkg is



  --==============================================================================
  -- Methods dedicated to this VVC
  -- Notes:
  --   - shared_vvc_cmd is initialised to C_VVC_CMD_DEFAULT, and also reset to this after every command
  --==============================================================================

  ----------------------------------------------------------
  -- SPI_MASTER
  ----------------------------------------------------------  
  procedure spi_master_transmit_and_receive(
    signal   VVCT               : inout t_vvc_target_record;
    constant vvc_instance_idx   : in integer;
    constant data               : in std_logic_vector;
    constant msg                : in string
  ) is
    constant proc_name          : string := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call          : string := proc_name & "(" & to_string(VVCT, vvc_instance_idx) & ")";
    variable v_normalised_data  : std_logic_vector(shared_vvc_cmd.data'length-1 downto 0) :=
        normalize_and_check(data, shared_vvc_cmd.data, ALLOW_WIDER_NARROWER, "data", "shared_vvc_cmd.data", proc_call & " called with to wide data. " & add_msg_delimiter(msg));    
  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    shared_vvc_cmd              := C_VVC_CMD_DEFAULT;
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, MASTER_TRANSMIT_AND_RECEIVE);
    shared_vvc_cmd.data(data'length-1 downto 0) := v_normalised_data;
    send_command_to_vvc(VVCT);
  end procedure;
  
  procedure spi_master_transmit_and_check(
    signal   VVCT               : inout t_vvc_target_record;
    constant vvc_instance_idx   : in integer;
    constant data               : in std_logic_vector;    
    constant data_exp           : in std_logic_vector;
    constant msg                : in string;
    constant alert_level        : in t_alert_level := ERROR
  ) is
    constant proc_name          : string := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call          : string := proc_name & "(" & to_string(VVCT, vvc_instance_idx) & ")";
    variable v_normalised_data  : std_logic_vector(shared_vvc_cmd.data'length-1 downto 0) :=
        normalize_and_check(data, shared_vvc_cmd.data, ALLOW_WIDER_NARROWER, "data", "shared_vvc_cmd.data", proc_call & " called with to wide data. " & add_msg_delimiter(msg));
  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    shared_vvc_cmd              := C_VVC_CMD_DEFAULT;
    set_general_target_and_command_fields(VVCT, vvc_instance_idx,  proc_call, msg, QUEUED, MASTER_TRANSMIT_AND_CHECK);
    shared_vvc_cmd.data         := v_normalised_data;
    shared_vvc_cmd.data_exp(data_exp'length-1 downto 0) := data_exp;
    shared_vvc_cmd.alert_level  := alert_level;
    send_command_to_vvc(VVCT);
  end procedure;

  procedure spi_master_transmit_only(
    signal   VVCT               : inout t_vvc_target_record;
    constant vvc_instance_idx   : in integer;
    constant data               : in std_logic_vector;
    constant msg                : in string
  ) is
    constant proc_name          : string := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call          : string := proc_name & "(" & to_string(VVCT, vvc_instance_idx) & ")";
    variable v_normalised_data  : std_logic_vector(shared_vvc_cmd.data'length-1 downto 0) :=
        normalize_and_check(data, shared_vvc_cmd.data, ALLOW_WIDER_NARROWER, "data", "shared_vvc_cmd.data", proc_call & " called with to wide data. " & add_msg_delimiter(msg));
  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    shared_vvc_cmd              := C_VVC_CMD_DEFAULT;
    -- Locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, MASTER_TRANSMIT_ONLY);
    shared_vvc_cmd.data         := v_normalised_data;   
    send_command_to_vvc(VVCT);
  end procedure;

  procedure spi_master_receive_only(
    signal   VVCT               : inout t_vvc_target_record;
    constant vvc_instance_idx   : in integer;
    constant msg                : in string
  ) is
    constant proc_name          : string := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call          : string := proc_name & "(" & to_string(VVCT, vvc_instance_idx) & ")";
  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    shared_vvc_cmd              := C_VVC_CMD_DEFAULT;
    -- Locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, MASTER_RECEIVE_ONLY);
    send_command_to_vvc(VVCT);
  end procedure;

  procedure spi_master_check_only(
    signal   VVCT               : inout t_vvc_target_record;
    constant vvc_instance_idx   : in integer;
    constant data_exp           : in std_logic_vector;
    constant msg                : in string;
    constant alert_level        : in t_alert_level := ERROR
  ) is
    constant proc_name          : string := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call          : string := proc_name & "(" & to_string(VVCT, vvc_instance_idx) & ")";
  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    shared_vvc_cmd              := C_VVC_CMD_DEFAULT;
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, MASTER_CHECK_ONLY);
    shared_vvc_cmd.data_exp(data_exp'length-1 downto 0) := data_exp;
    shared_vvc_cmd.alert_level  := alert_level;
    send_command_to_vvc(VVCT);
  end procedure;


  ----------------------------------------------------------
  -- SPI_SLAVE
  ----------------------------------------------------------
  procedure spi_slave_transmit_and_receive(
    signal   VVCT               : inout t_vvc_target_record;
    constant vvc_instance_idx   : in integer;
    constant data               : in std_logic_vector;
    constant msg                : in string
  ) is
    constant proc_name          : string := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call          : string := proc_name & "(" & to_string(VVCT, vvc_instance_idx) & ")";
    variable v_normalised_data  : std_logic_vector(shared_vvc_cmd.data'length-1 downto 0) :=
        normalize_and_check(data, shared_vvc_cmd.data, ALLOW_WIDER_NARROWER, "data", "shared_vvc_cmd.data", proc_call & " called with to wide data. " & add_msg_delimiter(msg));
  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    shared_vvc_cmd              := C_VVC_CMD_DEFAULT;
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, SLAVE_TRANSMIT_AND_RECEIVE);
    shared_vvc_cmd.data(data'length-1 downto 0) := v_normalised_data;
    send_command_to_vvc(VVCT);
  end procedure;

  procedure spi_slave_transmit_and_check(
    signal   VVCT               : inout t_vvc_target_record;
    constant vvc_instance_idx   : in integer;
    constant data               : in std_logic_vector;
    constant data_exp           : in std_logic_vector;
    constant msg                : in string;
    constant alert_level        : in t_alert_level := ERROR    
  ) is
    constant proc_name          : string := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call          : string := proc_name & "(" & to_string(VVCT, vvc_instance_idx) & ")";
    variable v_normalised_data  : std_logic_vector(shared_vvc_cmd.data'length-1 downto 0) :=
        normalize_and_check(data, shared_vvc_cmd.data, ALLOW_WIDER_NARROWER, "data", "shared_vvc_cmd.data", proc_call & " called with to wide data. " & add_msg_delimiter(msg));    
  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    shared_vvc_cmd              := C_VVC_CMD_DEFAULT;
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, SLAVE_TRANSMIT_AND_CHECK);
    shared_vvc_cmd.data         := v_normalised_data;
    shared_vvc_cmd.data_exp(data_exp'length-1 downto 0) := data_exp;
    send_command_to_vvc(VVCT);
  end procedure;
 
  procedure spi_slave_transmit_only(
    signal   VVCT               : inout t_vvc_target_record;
    constant vvc_instance_idx   : in integer;
    constant data               : in std_logic_vector;
    constant msg                : in string
  ) is
    constant proc_name          : string := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call          : string := proc_name & "(" & to_string(VVCT, vvc_instance_idx) & ")";
    variable v_normalised_data  : std_logic_vector(shared_vvc_cmd.data'length-1 downto 0) :=
        normalize_and_check(data, shared_vvc_cmd.data, ALLOW_WIDER_NARROWER, "data", "shared_vvc_cmd.data", proc_call & " called with to wide data. " & add_msg_delimiter(msg));
  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    shared_vvc_cmd              := C_VVC_CMD_DEFAULT;
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, SLAVE_TRANSMIT_ONLY);
    shared_vvc_cmd.data         := v_normalised_data;
    send_command_to_vvc(VVCT);
  end procedure;

  procedure spi_slave_receive_only(
    signal   VVCT               : inout t_vvc_target_record;
    constant vvc_instance_idx   : in integer;
    constant msg                : in string
  ) is
    constant proc_name          : string := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call          : string := proc_name & "(" & to_string(VVCT, vvc_instance_idx) & ")";
  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    shared_vvc_cmd              := C_VVC_CMD_DEFAULT;
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, SLAVE_RECEIVE_ONLY);
    send_command_to_vvc(VVCT);
  end procedure;

  procedure spi_slave_check_only(
    signal   VVCT               : inout t_vvc_target_record;
    constant vvc_instance_idx   : in integer;
    constant data               : in std_logic_vector;
    constant msg                : in string;
    constant alert_level        : in t_alert_level := ERROR
  ) is
    constant proc_name          : string := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call          : string := proc_name & "(" & to_string(VVCT, vvc_instance_idx) & ")";
  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    shared_vvc_cmd              := C_VVC_CMD_DEFAULT;
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, SLAVE_CHECK_ONLY);
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    shared_vvc_cmd.data_exp(data'length-1 downto 0) := data;
    shared_vvc_cmd.alert_level  := alert_level;
    send_command_to_vvc(VVCT);
  end procedure;



  


end package body vvc_methods_pkg;


