`timescale 1ns/1ps
module tb_ball;
    reg il, ir; reg [2:0] bx, by;
    // shared comparisons
    wire x0 = (bx==0) && il;
    wire x3 = (bx==4) && il;
    wire y0 = (by==0) && ir;
    wire y3 = (by==4) && ir;
    // ORIGINAL
    wire gt_x0 = il, gt_x1 = il && !x0, lt_x2 = il && !x3, lt_x3 = il;
    wire gt_y0 = ir, gt_y1 = ir && !y0, lt_y2 = ir && !y3, lt_y3 = ir;
    wire left_lobe   = gt_x0 && lt_x2 && gt_y1 && lt_y2;
    wire right_lobe  = gt_x1 && lt_x3 && gt_y1 && lt_y2;
    wire top_lobe    = gt_x1 && lt_x2 && gt_y0 && lt_y2;
    wire bottom_lobe = gt_x1 && lt_x2 && gt_y1 && lt_y3;
    wire old_in_ball = left_lobe || right_lobe || top_lobe || bottom_lobe;
    // SIMPLIFIED: in the box, and not a cut corner
    wire new_in_ball = il && ir && !((x0 || x3) && (y0 || y3));

    integer i, j, k, l, mm, n;
    initial begin
        mm=0; n=0;
        for (i=0;i<2;i=i+1) for (j=0;j<2;j=j+1)
          for (k=0;k<8;k=k+1) for (l=0;l<8;l=l+1) begin
            il=i[0]; ir=j[0]; bx=k[2:0]; by=l[2:0]; #1;
            n=n+1;
            if (old_in_ball !== new_in_ball) begin
                mm=mm+1;
                if (mm<=5) $display("  MISMATCH il=%b ir=%b bx=%0d by=%0d: old=%b new=%b",
                                    il,ir,bx,by,old_in_ball,new_in_ball);
            end
          end
        $display("Swept %0d combos (il x ir x ball_x 0-7 x ball_y 0-7): %0d mismatches", n, mm);
        if (mm==0) $display("PASS: in_ball simplification is bit-exact over the full state space");
        $finish;
    end
endmodule
