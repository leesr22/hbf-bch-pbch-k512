function automatic [M-1:0] bch_gf_multiply_generic(
    input [M-1:0] left,
    input [M-1:0] right
);
    reg [M-1:0] product;
    reg [M-1:0] multiplicand;
    reg [M-1:0] multiplier;
    integer bit_index;
    begin
        product = 0;
        multiplicand = left;
        multiplier = right;
        for (bit_index = 0; bit_index < M; bit_index = bit_index + 1) begin
            if (multiplier[0]) product = product ^ multiplicand;
            multiplier = multiplier >> 1;
            multiplicand = multiplicand[M-1]
                ? ((multiplicand << 1) ^ PRIMITIVE_POLYNOMIAL[M-1:0])
                : (multiplicand << 1);
        end
        bch_gf_multiply_generic = product;
    end
endfunction

function automatic [M-1:0] bch_alpha_power_generic(input integer signed exponent);
    reg [M-1:0] value;
    reg [M-1:0] base;
    integer signed normalized;
    integer power;
    begin
        normalized = exponent % FIELD_ORDER;
        if (normalized < 0) normalized = normalized + FIELD_ORDER;
        value = {{(M-1){1'b0}}, 1'b1};
        base = {{(M-2){1'b0}}, 2'b10};
        power = normalized;
        while (power != 0) begin
            if (power & 1) value = bch_gf_multiply_generic(value, base);
            base = bch_gf_multiply_generic(base, base);
            power = power >> 1;
        end
        bch_alpha_power_generic = value;
    end
endfunction
