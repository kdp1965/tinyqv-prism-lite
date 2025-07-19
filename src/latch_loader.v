module latch_loader #(
    parameter NUM_REGS = 8
)(
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire                  write_req,        // One-cycle pulse to initiate write
    input  wire  [31:0]          data_in,          // Incoming data from RISC-V
    input  wire  [5:0]           address,          // Input address
    output reg   [47:0]          config_data,      // Incoming data from RISC-V
    output wire                  busy,             // Indicates the FSM is busy
    output reg   [NUM_REGS-1:0]  latch_en          // Latch enables, active high
);

    localparam    IDX_BITS = NUM_REGS > 16 ? 5 : NUM_REGS > 8 ? 4 : 3;

    // Counter-based FSM
    localparam IDLE    = 2'd0;
    localparam SHIFT   = 2'd1;
    localparam WAIT    = 2'd2;

    reg  [1:0]           state, next_state;
    reg   [IDX_BITS-1:0] index;
    reg   [NUM_REGS-1:0] next_latch_en;
    wire                 load;

    // We are busy if we are not in IDLE state
    assign busy = state != IDLE;
    assign load = write_req && address == 6'hc;

    // Sequential state machine
    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n) begin
            state    <= IDLE;
            index    <= '0;
            latch_en <= '0;
        end else begin
            state    <= next_state;
            latch_en <= next_latch_en;
            if (state == IDLE && load)
                index <= NUM_REGS - 1;
            else if (state == WAIT)
                index <= index - 1;
        end
    end

    // FSM transitions
    always_comb begin
        next_state = state;
        case (state)
            IDLE:    if (load) next_state = SHIFT;
            SHIFT:   next_state = WAIT;
            WAIT:    next_state = (index == 0) ? IDLE : SHIFT;
            default: next_state = IDLE;
        endcase
    end

    // Latch enable logic
    always @*
    begin
        next_latch_en = '0;
        if (state == SHIFT)
            next_latch_en[index] = 1'b1;
    end

    // Data buffer
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            config_data <= '0;
        end else if (write_req) 
        begin 
            if (address == 6'h8)
               config_data[31:0] <= data_in;
            if (address == 6'hc)
               config_data[47:32] <= data_in[15:0];
        end
    end

endmodule
