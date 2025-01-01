`include "uvm_macros.svh";
import uvm_pkg::*;



class transaction extends uvm_sequence_item;
  `uvm_object_utils(transaction);
  
  function new(string path="trans");
    super.new(path);
  endfunction
  
  rand bit[7:0]addr;
  rand bit[7:0]wdata;
  bit rst;
  bit strb;
  bit we;
  bit [7:0]rdata;
  bit ack;
  bit [1:0]op;
endclass

class rstseq extends uvm_sequence#(transaction);
  `uvm_object_utils(rstseq);
  transaction trans;
  function new(string path="rstseq");
    super.new(path);
  endfunction
  
  
  virtual task body();
    repeat(10)
      begin
        trans=transaction::type_id::create("trans");
        start_item(trans);
        assert(trans.randomize());
        trans.op=0;
        trans.rst=1;
        `uvm_info("RST","RESET OCCURED",UVM_NONE);
        finish_item(trans);
      end
  endtask
endclass

class write extends uvm_sequence#(transaction);
  `uvm_object_utils(write);
  transaction trans;
  function new(string path="write");
    super.new(path);
  endfunction
  
  
  virtual task body();
    repeat(10)
      begin
        trans=transaction::type_id::create("trans");
        start_item(trans);
        assert(trans.randomize());
        trans.op=1;
        trans.rst=0;
        trans.strb=1;
        trans.we=1;
        
        `uvm_info("WRT",$sformatf("DATA:%0d ADDR:%0d",trans.wdata,trans.addr),UVM_NONE);
        finish_item(trans);
      end
  endtask
endclass

class read extends uvm_sequence#(transaction);
  `uvm_object_utils(read);
  transaction trans;
  function new(string path="read");
    super.new(path);
  endfunction
  
  
  virtual task body();
    repeat(10)
      begin
        trans=transaction::type_id::create("trans");
        start_item(trans);
        assert(trans.randomize());
        trans.rst=0;
        trans.strb=1;
        trans.we=0;
        trans.op=2;
        `uvm_info("READ",$sformatf("ADDR:%0d",trans.addr),UVM_NONE);
        finish_item(trans);
      end
  endtask
endclass

class driver extends uvm_driver#(transaction);
  `uvm_component_utils(driver);
  transaction trans;
  virtual wb_if inf;
  function new(string path="drv",uvm_component parent=null);
    super.new(path,parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    trans=transaction::type_id::create("trans");
    
    if(!uvm_config_db #(virtual wb_if)::get(this,"","inf",inf));
       `uvm_info("DRV","ERROR IN CONFIG OF DRIVER",UVM_NONE);
  endfunction
  
  task reset();
    repeat(5)
      begin
        inf.rst<=1;
        inf.we<=0;
        inf.strb<=0;
        inf.addr<=0;
        inf.wdata<=0;
        inf.rdata<=0;
        inf.ack<=0;
        `uvm_info("DRV_RST","DUT RESET DONE",UVM_NONE);
        @(posedge inf.clk);
      end
  endtask
  
  virtual task run_phase(uvm_phase phase);
    reset();
    forever
      begin
        seq_item_port.get_next_item(trans);
        if(trans.op==0)
          begin
            inf.rst<=1;
            inf.we<=0;
            inf.strb<=0;
            inf.addr<=0;
            inf.wdata<=0;
            inf.rdata<=0;
            inf.ack<=0;
            @(posedge inf.clk);
          end
        else if(trans.op==1)
          begin
            inf.we<=1;
            inf.strb<=1;
            inf.rst<=0;
            inf.addr<=trans.addr;
            inf.wdata<=trans.wdata;
            `uvm_info("DRV_WRT",$sformatf("WRITE OPERATION DETECTED at ADDR:%0d WDATA;%0d",trans.addr,trans.wdata),UVM_NONE);
            @(posedge inf.ack);

          end
        else if(trans.op==2)
          begin
            inf.we<=0;
            inf.strb<=1;
            inf.rst<=0;
            inf.addr<=trans.addr;
            `uvm_info("DRV_RD",$sformatf("READ OPERATION DETECTED at ADDR:%0d",trans.addr),UVM_NONE);
            @(posedge inf.ack);


          end
        seq_item_port.item_done(trans);
      end
  endtask
endclass

class monitor extends uvm_monitor;
  `uvm_component_utils(monitor);
  transaction trans;
  virtual wb_if inf;
  uvm_analysis_port #(transaction)send;
  function new(string path="mon",uvm_component parent=null);
    super.new(path,parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    trans=transaction::type_id::create("trans");
    send=new("send",this);
    if(!uvm_config_db #(virtual wb_if)::get(this,"","inf",inf));
       `uvm_info("DRV","ERROR IN CONFIG OF DRIVER",UVM_NONE);
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    forever
      begin
        @(posedge inf.clk);
        if(inf.rst)
          begin
            `uvm_info("MON_RST","RESET DETECTED",UVM_NONE);
            trans.op=0;
            send.write(trans);
          end
        else if(inf.strb && inf.we)
          begin
            trans.addr=inf.addr;
            trans.wdata=inf.wdata;
            trans.ack=inf.ack;
            trans.op=1;
            @(posedge inf.ack);
            `uvm_info("MON_WRT",$sformatf("WRITE OPERATION DONE AT ADDR:%0d with DATA:%0d ACK:%0d",trans.addr,trans.wdata,trans.ack),UVM_NONE);
            send.write(trans);
          end
        else if(inf.strb && !inf.we)
          begin
            trans.op=2;
            trans.addr=inf.addr;
//             @(posedge inf.ack);
//             #10;
            trans.rdata=inf.rdata;
            #20;
            `uvm_info("MON_RD",$sformatf("READ OPERATION DONE AT ADDR:%0d with DATA:%0d",trans.addr,trans.rdata),UVM_NONE);
            send.write(trans);
          end
      end
  endtask
endclass

class scoreboard extends uvm_scoreboard;
  `uvm_component_utils(scoreboard);
  transaction trans;
  uvm_analysis_imp #(transaction,scoreboard)recv;
  bit [7:0] mem[256];
  bit [7:0] temp;
  function new(string path="scb",uvm_component parent=null);
    super.new(path,parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    trans=transaction::type_id::create("trans");
    recv=new("recv",this);
  endfunction
  
  virtual function void write(transaction tr);
    trans=tr;
    if(trans.op==0)
      begin
        `uvm_info("SCB","RESET OCCURED",UVM_NONE);
      end
    else if(trans.op==1)
      begin
        mem[trans.addr]=trans.wdata;
        `uvm_info("SCO_WRITE",$sformatf("DATA WRITE DONE"),UVM_NONE);
      end
    else if(trans.op==2)
      begin
        temp=mem[trans.addr];
        if(temp==trans.rdata)
          begin
            `uvm_info("SCB","PASSED",UVM_NONE);
          end
        else
          begin
            `uvm_info("SCB","FAILED",UVM_NONE);
          end
      end
    $display("-------------------------------");
  endfunction
endclass

class agent extends uvm_agent;
  `uvm_component_utils(agent);
  driver drv;
  monitor mon;
  uvm_sequencer #(transaction)seqr;
  function new(string path="a",uvm_component parent=null);
    super.new(path,parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    drv=driver::type_id::create("drv",this);
    mon=monitor::type_id::create("mon",this);
    seqr=uvm_sequencer#(transaction)::type_id::create("seqr",this);
  endfunction
  
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    drv.seq_item_port.connect(seqr.seq_item_export);
  endfunction
endclass

class env extends uvm_env;
  `uvm_component_utils(env);
  agent a;
  scoreboard scb;
  function new(string path="env",uvm_component parent=null);
    super.new(path,parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    a=agent::type_id::create("a",this);
    scb=scoreboard::type_id::create("scb",this);
  endfunction
  
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    a.mon.send.connect(scb.recv);
  endfunction
endclass

class test extends uvm_test;
  `uvm_component_utils(test);
  env e;
  rstseq rest;
  write wr;
  read rd;
  function new(string path="test",uvm_component parent=null);
    super.new(path,parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    e=env::type_id::create("e",this);
    rest=rstseq::type_id::create("rest",this);
    wr=write::type_id::create("wr",this);
    rd=read::type_id::create("rd",this);
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    rest.start(e.a.seqr);
    wr.start(e.a.seqr);
    rd.start(e.a.seqr);
    #50;
    phase.drop_objection(this);
  endtask
endclass

module tb;
  wb_if inf();
  mem_wb DUT(.clk(inf.clk),.we(inf.we),.strb(inf.strb),.rst(inf.rst),.addr(inf.addr),.wdata(inf.wdata),.rdata(inf.rdata),.ack(inf.ack));
  
  initial
    begin
      inf.clk=0;
    end
  
  always
    #10 inf.clk=~inf.clk;
  
  initial
    begin
      uvm_config_db #(virtual wb_if)::set(null,"*","inf",inf);
      run_test("test");
    end
endmodule
