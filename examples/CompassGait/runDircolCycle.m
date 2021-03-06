function [utraj,xtraj]=runDircolCycle(p);
% find stable limit cycle 

if (nargin<1)
  p = CompassGaitPlant();
end

% numbers from the first step of the passive sim 
x0 = [0;0;2;-.4];  
t1 = .417; 
x1 = [-.326;.22;-.381;-1.1];
tf = .713;
xf = x0;
N=15;
utraj0 = {PPTrajectory(foh(linspace(0,t1,N),zeros(1,N))),PPTrajectory(foh(linspace(0,tf-t1,N),zeros(1,N)))};
utraj0{1} = utraj0{1}.setOutputFrame(p.getInputFrame);
utraj0{2} = utraj0{2}.setOutputFrame(p.getInputFrame);

con.mode{1}.mode_num = 1;
con.mode{2}.mode_num = 2;

con.mode{1}.u.lb = p.umin;
con.mode{1}.u.ub = p.umax;
con.mode{2}.u.lb = p.umin;
con.mode{2}.u.ub = p.umax;

% make sure I take a reasonable sized step:
con.mode{1}.x0.lb = [0;-inf;-inf;-inf];
con.mode{1}.x0.ub = [0;inf;inf;inf];
con.mode{1}.xf.lb = [.1;-inf;-inf;-inf];

con.u_const_across_transitions=true;
con.periodic = true;

con.mode{1}.T.lb = .2;   
con.mode{1}.T.ub = .5;
con.mode{2}.T.lb = .2;   
con.mode{2}.T.ub = .5;

options.method='dircol';
options.xtape0='simulate';

tic
%options.grad_test = true;
[utraj,xtraj,info] = trajectoryOptimization(p,{@cost,@cost},{@finalcost,@finalcost},{x0, x1},utraj0,con,options);
if (info~=1) error('failed to find a trajectory'); end
toc

if (nargout<1)
  v = CompassGaitVisualizer(p);
  figure(1); clf;
  fnplt(utraj);
  
  figure(2); clf; hold on;
  fnplt(xtraj,[2 4]);
  fnplt(xtraj,[3 5]);
  
  playback(v,xtraj);
  
end

end



      function [g,dg] = cost(t,x,u);
        R = 1;
        g = sum((R*u).*u,1);
        dg = [zeros(1,1+size(x,1)),2*u'*R];
      end
      
      function [h,dh] = finalcost(t,x)
        h=0;
        dh = [0,zeros(1,size(x,1))];
      end
      
