#define PI radians(180.)
float clip(float a) { return clamp(a,-1.,1.); }
float theta(float x) { return smoothstep(0., 0.01, x); }
float _sin(float a) { return sin(2. * PI * mod(a,1.)); }
float _sin(float a, float p) { return sin(2. * PI * mod(a,1.) + p); }
float _unisin(float a,float b) { return (.5*_sin(a) + .5*_sin((1.+b)*a)); }
float _sq(float a) { return sign(2.*fract(a) - 1.); }
float _sq(float a,float pwm) { return sign(2.*fract(a) - 1. + pwm); }
float _psq(float a) { return clip(50.*_sin(a)); }
float _psq(float a, float pwm) { return clip(50.*(_sin(a) - pwm)); } 
float _tri(float a) { return (4.*abs(fract(a)-.5) - 1.); }
float _saw(float a) { return (2.*fract(a) - 1.); }
float quant(float a,float div,float invdiv) { return floor(div*a+.5)*invdiv; }
float quanti(float a,float div) { return floor(div*a+.5)/div; }
float freqC1(float note){ return 32.7 * pow(2.,note/12.); }
float minus1hochN(int n) { return (1. - 2.*float(n % 2)); }

#define pat4(a,b,c,d,x) mod(x,1.)<.25 ? a : mod(x,1.)<.5 ? b : mod(x,1.) < .75 ? c : d

const float BPM = 80.;
const float BPS = BPM/60.;
const float SPB = 60./BPM;

const float Fsample = 44100.; // I think?

float doubleslope(float t, float a, float d, float s)
{
    return smoothstep(-.00001,a,t) - (1.-s) * smoothstep(0.,d,t-a);
}

float s_atan(float a) { return 2./PI * atan(a); }
float s_crzy(float amp) { return clamp( s_atan(amp) - 0.1*cos(0.9*amp*exp(amp)), -1., 1.); }
float squarey(float a, float edge) { return abs(a) < edge ? a : floor(4.*a+.5)*.25; } 

float supershape(float s, float amt, float A, float B, float C, float D, float E)
{
    float w;
    float m = sign(s);
    s = abs(s);

    if(s<A) w = B * smoothstep(0.,A,s);
    else if(s<C) w = C + (B-C) * smoothstep(C,A,s);
    else if(s<=D) w = s;
    else if(s<=1.)
    {
        float _s = (s-D)/(1.-D);
        w = D + (E-D) * (1.5*_s*(1.-.33*_s*_s));
    }
    else return 1.;
    
    return m*mix(s,w,amt);
}

float GAC(float t, float offset, float a, float b, float c, float d, float e, float f, float g)
{
    t = t - offset;
    return t<0. ? 0. : a + b*t + c*t*t + d*sin(e*t) + f*exp(-g*t);
}

float TRISQ(float t, float f, int MAXN, float MIX, float INR, float NDECAY, float RES, float RES_Q)
{
    float ret = 0.;
    
    int Ninc = 8; // try this: leaving out harmonics...
    
    for(int N=0; N<=MAXN; N+=Ninc)
    {
        float mode     = 2.*float(N) + 1.;
        float inv_mode = 1./mode; 		// avoid division? save table of Nmax <= 20 in some array or whatever
        float comp_TRI = (N % 2 == 1 ? -1. : 1.) * inv_mode*inv_mode;
        float comp_SQU = inv_mode;
        float filter_N = pow(1. + pow(float(N) * INR,2.*NDECAY),-.5) + RES * exp(-pow(float(N)*INR*RES_Q,2.));

        ret += (MIX * comp_TRI + (1.-MIX) * comp_SQU) * filter_N * _sin(mode * f * t);
    }
    
    return ret;
}

float QTRISQ(float t, float f, float QUANT, int MAXN, float MIX, float INR, float NDECAY, float RES, float RES_Q)
{
    return TRISQ(quant(t,QUANT,1./QUANT), f, MAXN, MIX, INR, NDECAY, RES, RES_Q);
}

float env_ADSR(float x, float L, float A, float D, float S, float R)
{
    float att = x/A;
    float dec = 1. - (1.-S)*(x-A)/D;
    float rel = (x <= L-R) ? 1. : (L-x)/R;
    return (x < A ? att : (x < A+D ? dec : S)) * rel;    
}

float env_ADSRexp(float x, float L, float A, float D, float S, float R)
{
    float att = pow(x/A,8.);
    float dec = S + (1.-S) * exp(-(x-A)/D);
    float rel = (x <= L-R) ? 1. : pow((L-x)/R,4.);
    return (x < A ? att : dec) * rel;    
}


float macesaw(float t, float f, float CO, float Q, float det1, float det2, float res, float resQ)
{
    float s = 0.;
    float inv_CO = 1./CO;
    float inv_resQ = 1./resQ;
    float p = f*t;
        for(int N=1; N<=200; N++)
        {
            // saw
            float sawcomp = 2./PI * (1. - 2.*float(N % 2)) * 1./float(N);
            float filterN  = pow(1. + pow(float(N)*f*inv_CO,Q),-.5)
                     + res * exp(-pow((float(N)*f-CO)*inv_resQ,2.));
            
            if(abs(filterN*sawcomp) < 1e-6) break;
        		
            if(det1 > 0. || det2 > 0.)
            {
                s += 0.33 * (_sin(float(N)*p) + _sin(float(N)*p*(1.+det1)) + _sin(float(N)*p*(1.+det2)));
            }
            else
            {
                s += filterN * sawcomp * _sin(float(N)*p);
            }
        }
    return s;
}

float THESYNTH(float t, float B, float Bon, float Boff, float note, int Bsyn)
{
    float Bprog = B-Bon;
    float Bproc = Bprog/(Boff-Bon);
    float L = Boff-Bon;
    float tL = SPB*L;
    float _t = SPB*(B-Bon);
    float f = freqC1(note);
	float vel = 1.;

    float env = theta(B-Bon) * theta(Boff-B);
	float s = _sin(t*f);

	if(Bsyn == 0){}
    else if(Bsyn == 1){
      s = ((s_atan(_sin(.5*f*(t-0.0))+_sin((1.-.01)*.5*f*(t-0.0)))+theta(_t)*exp(-.03*_t)*.15*_sin(.5*f*(t-0.0),_sin(.5*f*(t-0.0)))+theta(_t)*exp(-.03*_t)*.8*(_sin(2.5198*.5*f*((t-0.0)-0.0))
      +_sin(2.5198*.5*f*((t-0.0)-1.0e-02))
      +_sin(2.5198*.5*f*((t-0.0)-2.0e-02))
      +_sin(2.5198*.5*f*((t-0.0)-3.0e-02)))*(.7+.5*_tri(.5*Bprog+0.)))
      +(s_atan(_sin(.5*f*(t-3.0e-01))+_sin((1.-.01)*.5*f*(t-3.0e-01)))+theta(_t)*exp(-.03*_t)*.15*_sin(.5*f*(t-3.0e-01),_sin(.5*f*(t-3.0e-01)))+theta(_t)*exp(-.03*_t)*.8*(_sin(2.5198*.5*f*((t-3.0e-01)-0.0))
      +_sin(2.5198*.5*f*((t-3.0e-01)-1.0e-02))
      +_sin(2.5198*.5*f*((t-3.0e-01)-2.0e-02))
      +_sin(2.5198*.5*f*((t-3.0e-01)-3.0e-02)))*(.7+.5*_tri(.5*Bprog+0.)))
      +(s_atan(_sin(.5*f*(t-6.0e-01))+_sin((1.-.01)*.5*f*(t-6.0e-01)))+theta(_t)*exp(-.03*_t)*.15*_sin(.5*f*(t-6.0e-01),_sin(.5*f*(t-6.0e-01)))+theta(_t)*exp(-.03*_t)*.8*(_sin(2.5198*.5*f*((t-6.0e-01)-0.0))
      +_sin(2.5198*.5*f*((t-6.0e-01)-1.0e-02))
      +_sin(2.5198*.5*f*((t-6.0e-01)-2.0e-02))
      +_sin(2.5198*.5*f*((t-6.0e-01)-3.0e-02)))*(.7+.5*_tri(.5*Bprog+0.)))
      +(s_atan(_sin(.5*f*(t-9.0e-01))+_sin((1.-.01)*.5*f*(t-9.0e-01)))+theta(_t)*exp(-.03*_t)*.15*_sin(.5*f*(t-9.0e-01),_sin(.5*f*(t-9.0e-01)))+theta(_t)*exp(-.03*_t)*.8*(_sin(2.5198*.5*f*((t-9.0e-01)-0.0))
      +_sin(2.5198*.5*f*((t-9.0e-01)-1.0e-02))
      +_sin(2.5198*.5*f*((t-9.0e-01)-2.0e-02))
      +_sin(2.5198*.5*f*((t-9.0e-01)-3.0e-02)))*(.7+.5*_tri(.5*Bprog+0.)))
      +(s_atan(_sin(.5*f*(t-1.2))+_sin((1.-.01)*.5*f*(t-1.2)))+theta(_t)*exp(-.03*_t)*.15*_sin(.5*f*(t-1.2),_sin(.5*f*(t-1.2)))+theta(_t)*exp(-.03*_t)*.8*(_sin(2.5198*.5*f*((t-1.2)-0.0))
      +_sin(2.5198*.5*f*((t-1.2)-1.0e-02))
      +_sin(2.5198*.5*f*((t-1.2)-2.0e-02))
      +_sin(2.5198*.5*f*((t-1.2)-3.0e-02)))*(.7+.5*_tri(.5*Bprog+0.)))
      +(s_atan(_sin(.5*f*(t-1.5))+_sin((1.-.01)*.5*f*(t-1.5)))+theta(_t)*exp(-.03*_t)*.15*_sin(.5*f*(t-1.5),_sin(.5*f*(t-1.5)))+theta(_t)*exp(-.03*_t)*.8*(_sin(2.5198*.5*f*((t-1.5)-0.0))
      +_sin(2.5198*.5*f*((t-1.5)-1.0e-02))
      +_sin(2.5198*.5*f*((t-1.5)-2.0e-02))
      +_sin(2.5198*.5*f*((t-1.5)-3.0e-02)))*(.7+.5*_tri(.5*Bprog+0.)))
      +(s_atan(_sin(.5*f*(t-1.8))+_sin((1.-.01)*.5*f*(t-1.8)))+theta(_t)*exp(-.03*_t)*.15*_sin(.5*f*(t-1.8),_sin(.5*f*(t-1.8)))+theta(_t)*exp(-.03*_t)*.8*(_sin(2.5198*.5*f*((t-1.8)-0.0))
      +_sin(2.5198*.5*f*((t-1.8)-1.0e-02))
      +_sin(2.5198*.5*f*((t-1.8)-2.0e-02))
      +_sin(2.5198*.5*f*((t-1.8)-3.0e-02)))*(.7+.5*_tri(.5*Bprog+0.)))
      +(s_atan(_sin(.5*f*(t-2.1))+_sin((1.-.01)*.5*f*(t-2.1)))+theta(_t)*exp(-.03*_t)*.15*_sin(.5*f*(t-2.1),_sin(.5*f*(t-2.1)))+theta(_t)*exp(-.03*_t)*.8*(_sin(2.5198*.5*f*((t-2.1)-0.0))
      +_sin(2.5198*.5*f*((t-2.1)-1.0e-02))
      +_sin(2.5198*.5*f*((t-2.1)-2.0e-02))
      +_sin(2.5198*.5*f*((t-2.1)-3.0e-02)))*(.7+.5*_tri(.5*Bprog+0.)))
      +(s_atan(_sin(.5*f*(t-2.4))+_sin((1.-.01)*.5*f*(t-2.4)))+theta(_t)*exp(-.03*_t)*.15*_sin(.5*f*(t-2.4),_sin(.5*f*(t-2.4)))+theta(_t)*exp(-.03*_t)*.8*(_sin(2.5198*.5*f*((t-2.4)-0.0))
      +_sin(2.5198*.5*f*((t-2.4)-1.0e-02))
      +_sin(2.5198*.5*f*((t-2.4)-2.0e-02))
      +_sin(2.5198*.5*f*((t-2.4)-3.0e-02)))*(.7+.5*_tri(.5*Bprog+0.)))
      +(s_atan(_sin(.5*f*(t-2.7))+_sin((1.-.01)*.5*f*(t-2.7)))+theta(_t)*exp(-.03*_t)*.15*_sin(.5*f*(t-2.7),_sin(.5*f*(t-2.7)))+theta(_t)*exp(-.03*_t)*.8*(_sin(2.5198*.5*f*((t-2.7)-0.0))
      +_sin(2.5198*.5*f*((t-2.7)-1.0e-02))
      +_sin(2.5198*.5*f*((t-2.7)-2.0e-02))
      +_sin(2.5198*.5*f*((t-2.7)-3.0e-02)))*(.7+.5*_tri(.5*Bprog+0.))));}
    else if(Bsyn == 2){
      s = _sin(.5*f*t)
      +.2*_sin(.5*f*floor(256.*t+.5)/256.);}
    
	return clamp(env,0.,1.) * s_atan(s);
}

float BA8(float x, int pattern)
{
    x = mod(x,1.);
    float ret = 0.;
	for(int b = 0; b < 8; b++)
    	if ((pattern & (1<<b)) > 0) ret += step(x,float(7-b)/8.);
    return ret * .125;
}

float mainSynth(float time)
{
    int NO_trks = 1;
    int trk_sep[2] = int[2](0,1);
    int trk_syn[1] = int[1](1);
    float mod_on[1] = float[1](0.);
    float mod_off[1] = float[1](2.);
    int mod_ptn[1] = int[1](0);
    float mod_transp[1] = float[1](0.);
    float max_mod_off = 2.;
    int drum_index = 3;
    float drum_synths = 11.;
    int NO_ptns = 1;
    int ptn_sep[2] = int[2](0,15);
    float note_on[15] = float[15](0.,.125,.25,.375,.5,.625,.75,.875,1.,1.125,1.25,1.375,1.5,1.625,1.75);
    float note_off[15] = float[15](.25,.25,.5,.5,.75,.75,1.,1.,1.25,1.25,1.5,1.5,1.75,2.,2.);
    float note_pitch[15] = float[15](24.,43.,26.,45.,27.,47.,29.,48.,31.,47.,33.,45.,35.,57.,36.);
    float note_vel[15] = float[15](1.,1.,1.,1.,1.,1.,1.,1.,1.,1.,1.,1.,1.,1.,1.);
    
    float max_release = 0.3;   
    float track_norm[1] = float[1](1.);
   
    float r = 0.;
    float d = 0.;

    //which beat are we at?
    float BT = mod(BPS * time, max_mod_off); // mod for looping
    if(BT > max_mod_off) return r;

    // drum / sidechaining parameters
    float amt_drum = 0.3;
    float r_sidechain = 1.;
    float amt_sidechain = 0.99;
    float dec_sidechain = 0.6;

    float Bon = 0.;
    float Boff = 0.;

    for(int trk = 0; trk < NO_trks; trk++)
    {
        int TLEN = trk_sep[trk+1] - trk_sep[trk];
       
        int _mod = TLEN;
        for(int i=0; i<TLEN; i++) if(BT < mod_off[(trk_sep[trk]+i)]) {_mod = i; break;}
        if(_mod == TLEN) continue;
       
        float B = BT - mod_on[trk_sep[trk]+_mod];
       
        int ptn = mod_ptn[trk_sep[trk]+_mod];
        int PLEN = ptn_sep[ptn+1] - ptn_sep[ptn];
       
        int _noteU = PLEN-1;
        for(int i=0; i<PLEN-1; i++) if(B < note_on[(ptn_sep[ptn]+i+1)]) {_noteU = i; break;}

        int _noteL = PLEN-1;
        for(int i=0; i<PLEN-1; i++) if(B <= note_off[(ptn_sep[ptn]+i)] + max_release) {_noteL = i; break;}
       
        for(int _note = _noteL; _note <= _noteU; _note++)
        {
            Bon    = note_on[(ptn_sep[ptn]+_note)];
            Boff   = note_off[(ptn_sep[ptn]+_note)];

            if(trk_syn[trk] == drum_index)
            {/*
                float Bdrum = mod(note_pitch[ptn_sep[ptn]+_note], drum_synths);
                float Bvel = 1.; //note_vel[(ptn_sep[ptn]+_note)] * pow(2.,mod_transp[_mod]/6.);

                float anticlick = 1.-exp(-1000.*(B-Bon));
                float _d = 0.;

                if(Bdrum < .01) // Sidechain
                {
                    r_sidechain = anticlick - amt_sidechain * theta(B-Bon) * smoothstep(-dec_sidechain,0.,Bon-B);
                }
                else if(Bdrum < 1.01) // Kick1
                {
                    r_sidechain = anticlick - amt_sidechain * theta(B-Bon) * smoothstep(-dec_sidechain,0.,Bon-B);
                    r_sidechain *= 0.5;
                    _d = facekick(B*SPB, Bon*SPB, Bvel);
                }
                else if(Bdrum < 2.01) // Kick2
                {
                    r_sidechain = anticlick - amt_sidechain * theta(B-Bon) * smoothstep(-dec_sidechain,0.,Bon-B);
                    r_sidechain *= 0.5;
                    _d = hardkick(B*SPB, Bon*SPB, Bvel);
                }
                else if(Bdrum < 3.01) // Snare1
                {
                    _d = snare(B*SPB, Bon*SPB, Bvel);
                }
                else if(Bdrum < 4.01) // HiHat
                {
                    _d = hut(B*SPB, Bon*SPB, Bvel);
                }               
                else if(Bdrum < 5.01) // Shake
                {
                    _d = shake(B*SPB, Bon*SPB, Bvel);
                }
                else if(Bdrum < 6.01) // ...
                {
                }         
                d += track_norm[trk] * _d;*/
            }
            else
            {
                r += track_norm[trk] * THESYNTH(time, B, Bon, Boff,
                                               note_pitch[(ptn_sep[ptn]+_note)] + mod_transp[_mod], trk_syn[trk]);
            }

        }
    }

    r_sidechain = 1.;
    amt_drum = .5;

    return s_atan(s_atan((1.-amt_drum) * r_sidechain * r + amt_drum * d));
//    return sign(snd) * sqrt(abs(snd)); // eine von Matzes "besseren" Ideen
}

vec2 mainSound(float t)
{
    //maybe this works in enhancing the stereo feel
    float stereo_width = 0.1;
    float stereo_delay = 0.00001;
   
    //float comp_l = mainSynth(t) + stereo_width * mainSynth(t - stereo_delay);
    //float comp_r = mainSynth(t) + stereo_width * mainSynth(t + stereo_delay);
   
    //return vec2(comp_l * .99999, comp_r * .99999);
   
    return vec2(mainSynth(t));
}