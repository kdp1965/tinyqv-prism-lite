module latch_loader #(
    parameter DEPTH    = 8,
    parameter WIDTH    = 64
)(
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire                  write_req,        // One-cycle pulse to initiate write
    input  wire  [31:0]          data_in,          // Incoming data from RISC-V
    input  wire  [2:0]           address,          // Input address
    output reg   [WIDTH-1:0]     config_data,      // Incoming data from RISC-V
    output wire                  busy,             // Indicates the FSM is busy
    output reg   [DEPTH-1:0]     latch_en          // Latch enables, active high
);

    localparam    IDX_BITS = DEPTH > 16 ? 5 : DEPTH > 8 ? 4 : 3;

    // Counter-based FSM
    localparam IDLE    = 2'd0;
    localparam SHIFT   = 2'd1;
    localparam WAIT    = 2'd2;

    reg  [1:0]           state, next_state;
    reg  [IDX_BITS-1:0]  index;
    reg  [DEPTH-1:0]     next_latch_en;
    wire                 load;

    // We are busy if we are not in IDLE state
    assign busy = state != IDLE;
    assign load = write_req && address == 3'h4;

    // Sequential state machine
    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n) begin
            state    <= IDLE;
            index    <= {IDX_BITS{1'b0}};
            latch_en <= {DEPTH{1'b0}};
        end else begin
            state    <= next_state;
            latch_en <= next_latch_en;
            if (state == IDLE && load)
                index <= DEPTH - 1;
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
        next_latch_en = {DEPTH{1'b0}};
        if (state == SHIFT)
            next_latch_en[index] = 1'b1;
    end

    // Data buffer
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            config_data <= '0;
        end else if (write_req) 
        begin 
            if (address == 3'h0)
               config_data[31:0] <= data_in;
            if (address == 3'h4)
               config_data[WIDTH-1:32] <= data_in[WIDTH-32-1:0];
        end
    end

endmodule
