`timescale 1ns/1ns

module controller (
    input  logic       clk,
    input  logic       reset,         // Active-high reset
    input  logic [2:0] req,
    input  logic [2:0] done,
    output logic [4:0] mstate,        // Binary encoded internal state, see line 67 for encoding
    output logic [1:0] accmodule,     // Outputs: 0 = No Module, 1 = M1, 2 = M2, 3 = M3
    output int         nb_interrupts  // # of times M2 and M3 have been interrupted
);

    // Internal FSM state (One-hot encoded: 1 bit per state)
    typedef enum logic [7:0] {
        IDLE    = 8'b00000001,
        M1_INF  = 8'b00000010,
        M1_LIM1 = 8'b00000100,
        M1_LIM2 = 8'b00001000,
        M2_C1   = 8'b00010000,
        M2_C2   = 8'b00100000,
        M3_C1   = 8'b01000000,
        M3_C2   = 8'b10000000
    } state_t;

    state_t ps, ns;
    
    // Variables for readability: req[M1] instead of req[0]
    localparam int M1 = 0;
    localparam int M2 = 1;
    localparam int M3 = 2;

    // Variable to keep track of who (M2 or M3) last won the tie breaker
    // M2 wins initial tie breaker
    logic last_tie_m2;

    // --- State Register & Reset ---
    always_ff @(posedge clk or posedge reset) begin : seq_block
        // reset state to IDLE and tie breaker to M2
        if (reset) begin
            ps          <= IDLE; 
            last_tie_m2 <= 1'b0;
        end 
        // Update current state
        else begin
            ps <= ns;
            // Update tie breaker
            if ((ps == IDLE) && req == 3'b110) begin
                last_tie_m2 <= ~last_tie_m2;
            end
        end
    end : seq_block
  
    // --- Interrupt Counter ---
    // I did it this way instead of the way the skeleton code implies to limit
    // miscount due to jitter and requests made but not held to rising clk edge
    always_ff @(posedge clk or posedge reset) begin : counter_block
        // resets to 0
        if (reset) begin
            nb_interrupts <= 0;
        end 
        // interrupt occurs when M2 or M3 have mem control and M1 requests access
        else begin
            if (req[M1] && (ps == M2_C1 || ps == M2_C2 || ps == M3_C1 || ps == M3_C2)) begin
                nb_interrupts <= nb_interrupts + 1;
            end
        end
    end : counter_block

    // --- Next State and Output Logic ---
    always_comb begin : comb_block
        // Default assignments to prevent unintended latches
        mstate    = 5'd0; 
        accmodule = 2'b00;
        ns        = ps;
        
        // --- Binary State Encoding for mstate ---
        // Maps 1-hot present state bits to a 5-bit binary output
        unique case (ps)
            IDLE:    mstate = 5'd0;
            M1_INF:  mstate = 5'd1;
            M1_LIM1: mstate = 5'd2;
            M1_LIM2: mstate = 5'd3;
            M2_C1:   mstate = 5'd4;
            M2_C2:   mstate = 5'd5;
            M3_C1:   mstate = 5'd6;
            M3_C2:   mstate = 5'd7;
            default: mstate = 5'd31; 
        endcase

        // FSM Transitions using unique case due to 1-hot independent states
        unique case (ps)
            // if no mem module currently has mem control
            IDLE: begin
                accmodule = 2'b00;
                // first check M1 request
                if (req[M1]) ns = M1_INF;
                // then tiebreaker
                else if (req[M2] && req[M3]) begin
                    if (last_tie_m2) ns = M3_C1; else ns = M2_C1;
                end 
                // then M2 and M3
                else if (req[M2]) ns = M2_C1;
                else if (req[M3]) ns = M3_C1;
                // doesnt check interrupts bc thats impossible when the current state is IDLE
                else             ns = IDLE;
            end
            
            // if M1 currently has mem
            // doesnt check for interrupts bc M2 and M3 cant interrupt M1
            M1_INF, M1_LIM1, M1_LIM2: begin
                accmodule = 2'b01;
                // if done or on last interrupt state
                if (ps == M1_LIM2 || done[M1]) ns = IDLE;
                // if inf state, remain in inf
                else if (ps == M1_INF)         ns = M1_INF;
                // if interrupt state, inc clk cycle state
                else                           ns = M1_LIM2;
            end
            
            // if M2 currently has mem
            M2_C1, M2_C2: begin
                accmodule = 2'b10;
                // first check if M1 interrupts, no cycle delay handoff
                if (req[M1])                    ns = M1_LIM1;
                // then if times up or done
                else if (ps == M2_C2 || done[M2]) ns = IDLE;
                // if none of the above, inc clk cycle state
                else                            ns = M2_C2;
            end
            
            // if M3 currently has mem
            M3_C1, M3_C2: begin
                accmodule = 2'b11;
                // first check if M1 interrupts, no cycle delay handoff
                if (req[M1])                    ns = M1_LIM1;
                // then if times up or done
                else if (ps == M3_C2 || done[M3]) ns = IDLE;
                // if none of the above, inc clk cycle state
                else                            ns = M3_C2;
            end
            
            // default state to prevent unidentifiable state
            default: ns = IDLE;
        endcase

        // Handoff with no clk cycle break
        // If M1, M2, or M3 looses access this clk cycle, the previous logic will have set the state to IDLE
        // So, if the state is IDLE, check req line to ensure no delay handoff
        if (ns == IDLE) begin
            // first check M1
            if (req[M1]) begin
                // set next state
                ns = M1_INF;
            end 
            // then tie breaker
            else if (req[M2] && req[M3]) begin
                if (last_tie_m2) ns = M3_C1; else ns = M2_C1;
            end 
            // then M2 and M3
            else if (req[M2]) begin
                ns = M2_C1;
            end else if (req[M3]) begin
                ns = M3_C1;
            end
        end
    end : comb_block

endmodule
