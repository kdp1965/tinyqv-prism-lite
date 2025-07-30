module latch_loader #(
    parameter DEPTH    = 8,
    parameter WIDTH    = 64
)(
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire                  debug_wr,         // One-cycle pulse to initiate write
    input  wire                  latch_wr,         // Latch write signal properly timed
    input  wire  [31:0]          data_in,          // Incoming data from RISC-V
    input  wire  [5:0]           address,          // Input address
    output wire  [WIDTH-1:0]     config_data,      // Incoming data from RISC-V
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
    wire                 msb_enable;
    wire                 load;

    // Load when write_req and MSB of config data available
    assign load       = address == 6'h10 && debug_wr;
    assign msb_enable = address == 6'h14;

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
    assign config_data[31:0] = data_in;

    prism_latch_reg 
    #(
      .WIDTH(WIDTH-32)
    )
    config_msb
    (
        .rst_n       ( rst_n                   ),
        .enable      ( msb_enable              ),
        .wr          ( latch_wr                ),
        .data_in     ( data_in[WIDTH-32-1:0]   ),
        .data_out    ( config_data[WIDTH-1:32] )
    );

endmodule
