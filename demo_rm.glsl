
#define INFINITY 3.402823e+38
#define STACK_SIZE 32

#define FRAME_LOC 6u
#define BOUND_LOC (FRAME_LOC+2u)
#define NODE_LOC (BOUND_LOC+6u)

struct Traverse {
    uint node;
    float tmin,tmax;
} stk[STACK_SIZE];

uint read1u(uint i) {
#ifdef FROM_IMAGE
    uvec2 s=uvec2(textureSize(iChannel0,0));
    uvec2 uv=uvec2(i%s.x,i/s.x);
    vec4 tex=texelFetch(iChannel0,ivec2(uv),0);
    uvec4 bytes=uvec4(tex*255.0).abgr;
    return (bytes.r<<24)|(bytes.g<<16)|(bytes.b<<8)|bytes.a;
#else
    uint w=uint(textureSize(iChannel0,0).x);
    uint x=i%w;
    uint y=i/w;
    return texelFetch(iChannel0,ivec2(x,y),0).r;
#endif
}

uvec2 read2u(uint i) {
    return uvec2(read1u(i),read1u(i+1u));
}

uvec3 read3u(uint i) {
    return uvec3(read2u(i),read1u(i+2u));
}

uvec4 read4u(uint i) {
    return uvec4(read3u(i),read1u(i+3u));
}

vec4 uint_to_vec4(uint v) {
    return vec4(v&0xffu,(v>>8u)&0xffu,(v>>16u)&0xffu,(v>>24u)&0xffu)/255.0;
}

uvec2 uint_to_uvec2(uint v) {
    return uvec2(v&0xffffu,(v>>16u)&0xffffu);
}

vec2 fromBarycentric(float b1,float b2,vec2 a0,vec2 a1,vec2 a2) {
    return (1.0-b1-b2 )*a0+b1*a1+b2*a2;
}

vec3 fromBarycentric(float b1,float b2,vec3 a0,vec3 a1,vec3 a2) {
    return (1.0-b1-b2 )*a0+b1*a1+b2*a2;
}

vec4 fromBarycentric(float b1,float b2,vec4 a0,vec4 a1,vec4 a2) {
    return (1.0-b1-b2 )*a0+b1*a1+b2*a2;
}

float dot2( in vec3 v ) { return dot(v,v); }
float udTriangle( vec3 p, vec3 a, vec3 b, vec3 c ) {
    vec3 ba = b - a; vec3 pa = p - a;
    vec3 cb = c - b; vec3 pb = p - b;
    vec3 ac = a - c; vec3 pc = p - c;
    vec3 nor = cross( ba, ac );

    return sqrt(
    (sign(dot(cross(ba,nor),pa)) +
     sign(dot(cross(cb,nor),pb)) +
     sign(dot(cross(ac,nor),pc))<2.0)
     ?
     min( min(
     dot2(ba*clamp(dot(ba,pa)/dot2(ba),0.0,1.0)-pa),
     dot2(cb*clamp(dot(cb,pb)/dot2(cb),0.0,1.0)-pb) ),
     dot2(ac*clamp(dot(ac,pc)/dot2(ac),0.0,1.0)-pc) )
     :
     dot(nor,pa)*dot(nor,pa)/dot2(nor) );
}
float udBox( vec3 p, vec3 b ) {
  return length(max(abs(p)-b,0.0));
}

bool intersectTriangle(vec3 ro,vec3 rd,vec3 p0,vec3 p1,vec3 p2,out vec2 bcOut,out float tOut) {
    //Compute s1
    vec3 e1 = p1 - p0;
    vec3 e2 = p2 - p0;
    vec3 s1 = cross(rd, e2);
    float divisor = dot(s1, e1);

    if (divisor == 0.0) {
        return false;
    }

    float invDivisor = 1.0 / divisor;

    //Compute first barycentric coordinate
    vec3 d = ro - p0;
    float b1 = dot(d, s1) * invDivisor;

    if(b1 < 0.0 || b1 > 1.0) {
        return false;
    }

    //Compute second barycentric coordinate
    vec3 s2 = cross(d, e1);
    float b2 = dot(rd, s2) * invDivisor;

    if (b2 < 0.0 || b1 + b2 > 1.0) {
        return false;
    }

    //Compute t to intersection point
    float t = dot(e2, s2) * invDivisor;

    //
    tOut = t;
    bcOut=vec2(b1,b2);
    return true;
}

bool searchTree(vec3 P,vec3 V,vec3 invV,float rayMax,
                inout uint stkNum, out float tminOut,out float tmaxOut,
                out uint primsStartOut,out uint primsNumOut) {

    while(stkNum>0u) {
        stkNum--;
        uint node=stk[stkNum].node;
        float tmin=stk[stkNum].tmin;
        float tmax=stk[stkNum].tmax;

        uint a=read1u(node);
        uint type=a&3u;

        if(rayMax < tmin) {
            return false;
        }

        if(type==3u) { //leaf
            uint primsNum=a>>2u;

            if(primsNum!=0u) {
                primsStartOut=read1u(node+1u);
                primsNumOut=primsNum;
                tminOut=tmin;
                tmaxOut=tmax;
                return true;
            }
        } else { //branch
            uint axis=type;
            uint aboveChild=a>>2u;
            uint belowChild=node+2u;
            float split=uintBitsToFloat(read1u(node+1u));
            float tplane=(split-P[axis])*invV[axis];
            bool belowFirst=(P[axis]<split) || (P[axis] == split && V[axis] >= 0.0);
            uint firstNode=belowFirst?belowChild:aboveChild;
            uint secondNode=belowFirst?aboveChild:belowChild;

            if(tplane > tmax || tplane <= 0.0) {
                stk[stkNum].node=firstNode;
                stk[stkNum].tmin=tmin;
                stk[stkNum].tmax=tmax;
                stkNum++;
            } else if (tplane < tmin) {
                stk[stkNum].node=secondNode;
                stk[stkNum].tmin=tmin;
                stk[stkNum].tmax=tmax;
                stkNum++;
            } else {
                stk[stkNum].node=secondNode;
                stk[stkNum].tmin=tplane;
                stk[stkNum].tmax=tmax;
                stkNum++;
                stk[stkNum].node=firstNode;
                stk[stkNum].tmin=tmin;
                stk[stkNum].tmax=tplane;
                stkNum++;
            }
        }
    }

    return false;
}

bool intersectAabb(vec3 P,vec3 invV,vec3 bMin,vec3 bMax, out float enterOut,out float leaveOut) {

    vec3 tmin = (bMin - P) * invV;
    vec3 tmax = (bMax - P) * invV;

    vec3 tnear = min(tmin, tmax);
    vec3 tfar = max(tmin, tmax);
    float enter = max(tnear.x, max(tnear.y, tnear.z)); //max(tnear.x, 0.0)
    float exit = min(tfar.x, min(tfar.y, tfar.z));

    enterOut=enter;
    leaveOut=exit;
    return exit > max(enter, 0.0); //exit>0.0 && enter<exit
}

bool intersectTree(vec3 P,vec3 V,vec3 invV,vec3 bmin,vec3 bmax,
                   out uvec4 out_tri, out vec2 out_bc, inout float last_t) {
    float tmin,tmax;

    if(!intersectAabb(P,invV,bmin,bmax,tmin,tmax)) {
        return false;
    }

    stk[0].node=NODE_LOC;
    stk[0].tmin=tmin;
    stk[0].tmax=tmax;

    uint stkNum=1u;
    uint primsStart,primsNum;
    
    vec3 boundSize=bmax-bmin;
    vec3 boundPos=bmin+boundSize*0.5;
    float ttt=0.0;

    while(searchTree(P,V,invV,INFINITY,stkNum,tmin,tmax,primsStart,primsNum)) {
        float prevDist=udBox( P-boundPos, boundSize );
        bool onBound=true;
        
        while(true) {
            for(uint i=0u;i<primsNum;i++) {
                vec3 ps[3];
                uint prim=(primsNum==1u)?primsStart:read1u(primsStart+i);
                uvec4 tri=uvec4(read3u(prim),prim);//triangle inds

                for(uint j=0u;j<3u;j++) {
                    ps[j]=uintBitsToFloat(read3u(tri[j]));
                }

                vec3 faceNor=normalize(cross(ps[1]-ps[0],ps[2]-ps[0]));

                float t;
                vec2 bc;
                float dist=udTriangle(P,ps[0],ps[1],ps[2]);
                
                if(dist<prevDist) {
                    prevDist=dist;
                    onBound=false;
                }
            }
            
            if(prevDist<0.1) {
                break;
            }
            
            P+=V*prevDist;
            ttt+=prevDist;
        
        }

        if(ttt >= tmin && ttt <= tmax) {
            break;
        }
    }

    return (ttt<INFINITY);
}

bool intersectTreeP(vec3 P,vec3 V,vec3 invV,vec3 bmin,vec3 bmax,float rayMax) {
    float tmin,tmax;

    if(!intersectAabb(P,invV,bmin,bmax,tmin,tmax)) {
        return false;
    }

    stk[0].node=NODE_LOC;
    stk[0].tmin=tmin;
    stk[0].tmax=tmax;

    uint stkNum=1u;
    uint primsStart,primsNum;

    while(searchTree(P,V,invV,rayMax,stkNum,tmin,tmax,primsStart,primsNum)) {
        for(uint i=0u;i<primsNum;i++) {
            vec2 bc;
            float t;
            vec3 ps[3];
            uint prim=(primsNum==1u)?primsStart:read1u(primsStart+i);
            uvec3 tri=read3u(prim);//triangle inds

            for(uint j=0u;j<3u;j++) {
                ps[j]=uintBitsToFloat(read3u(tri[j]));
            }

            if(intersectTriangle(P,V,ps[0],ps[1],ps[2],bc,t)) {
                if(t <= rayMax) {
                    return true;
                }
            }
        }
    }

    return false;
}

vec3 calcPtLightCol(vec3 P,vec3 N,vec3 lPos,vec3 lAtten,vec3 mCol,vec3 lCol,float shininess,float strength) {
    vec3 L=lPos.xyz-P;
    float lDist=length(L);
    L=L/lDist;
    float atten = 1.0/dot(lAtten,vec3(1.0,lDist,lDist*lDist));
    vec3 R=reflect(-L,N);
    float NdotL = max(0.0,dot(N,L));
    float NdotR = max(0.0, dot(N,R));
    float spec = (NdotL > 0.0)?pow(NdotR,shininess*128.0)*strength:0.0;
    float diffuse=NdotL;
    return lCol*(mCol*diffuse+spec)*atten;
}

float calcFlare(vec3 ro,vec3 rd,vec3 lightPos2,float size) {
    vec3 viewLightDir=normalize(lightPos2-ro);
    float viewLightDist=length(lightPos2-ro);
    float q = dot(rd,viewLightDir)*0.5+0.5;
    float o = (1.0/viewLightDist)*size;
    return clamp(pow(q,900.0/o)*1.0,0.0,2.0);
}

vec4 sampleNearest(vec2 tc,uint texStart,uvec2 texSize) {
    uvec2 tc2=uvec2(mod(tc,1.0)*vec2(texSize));
    uint ind=tc2.y*texSize.x+tc2.x;
    return uint_to_vec4(read1u(texStart+ind));
}

vec4 sampleLinear(vec2 TexCoord,uint texStart,uvec2 texSize) {
    vec2 texSizef=vec2(texSize);
    vec2 invTexSizef=1.0/texSizef;

    //vec2 uv=TexCoord*texSizef;
    //uvec2 uvi=uvec2(uv);
    vec2 uvf=fract(TexCoord*texSizef);// uv-vec2(uvi);

    vec4 n0 = sampleNearest(TexCoord,texStart,texSize);
    vec4 n1 = sampleNearest(TexCoord+vec2(invTexSizef.x,0.0),texStart,texSize);
    vec4 n2 = sampleNearest(TexCoord+vec2(0.0,invTexSizef.y),texStart,texSize) ;
    vec4 n3 = sampleNearest(TexCoord+invTexSizef,texStart,texSize);

    return mix ( mix(n0,n1,uvf.x), mix(n2,n3,uvf.x), uvf.y );

}


vec3 render(vec3 ro,vec3 rd) {
    vec3 invRd=1.0/rd;
    vec3 bmin=uintBitsToFloat(read3u(BOUND_LOC+0u));
    vec3 bmax=uintBitsToFloat(read3u(BOUND_LOC+3u));

    uvec4 tri;
    vec2 bc;
    float t=INFINITY;

    if(!intersectTree(ro,rd,invRd,bmin,bmax,tri,bc,t)) {
        return vec3(0.0);
    }

    //
    vec3 ns[3],cs[3];
    vec2 tcs[3];
    vec4 tangs[3];

    uint mtrl=read1u(tri.w+3u);
    vec4 mtrlCol=uint_to_vec4(read1u(mtrl+0u));

    //if(mtrl>) {return vec3(1.0,0.0,0.0);}

    for(uint j=0u;j<3u;j++) {
        uint ind=tri[j];

        ns[j]=(uint_to_vec4(read1u(ind+3u)).rgb*2.0-1.0);
        //cs[j]=uint_to_vec4(read1u(ind+10u)).rgb;
        tcs[j]=unpackHalf2x16(read1u(ind+4u));
        tangs[j]=uint_to_vec4(read1u(ind+5u))*2.0-1.0;

        // tangs[j]=uintBitsToFloat(read4u(ind+6u));
    }

    vec3 nor=normalize(fromBarycentric(bc.x,bc.y,ns[0],ns[1],ns[2]));
    vec3 mCol=vec3(1.0);//=fromBarycentric(bc.x,bc.y,cs[0],cs[1],cs[2]);
    vec2 tc=fromBarycentric(bc.x,bc.y,tcs[0],tcs[1],tcs[2]);


    uint texLoc0=read1u(mtrl+1u+0u);

    if(texLoc0!=0u) {
        uvec2 texSize0=uint_to_uvec2(read1u(texLoc0));
        if(useLinearFiltering) {
            mCol*=sampleLinear(tc,texLoc0+1u,texSize0).rgb;
        } else {
            mCol*=sampleNearest(tc,texLoc0+1u,texSize0).rgb;
        }

    }

    mCol*=mtrlCol.rgb;

    vec3 pt=ro+rd*t;
    vec3 eyeDir=normalize(ro-pt);

    vec3 lightPos2=lightPos;

    if(lightAnimate) {
        lightPos2+=vec3(cos(iTime*0.1)*sin(iTime*0.1)*1.0,0.0,-5.0+sin(iTime*0.5)*12.0);
    }


    //vec3 lightPos2=lightPos2+vec3(cos(iTime*0.25),0.0,sin(iTime*0.25))*2.0;
    vec3 lightDir=normalize(lightPos2-pt);
    vec3 invLightDir=1.0/lightDir;
    float lightDist=length(lightPos2-pt);

    //return dirLight(nor,eyeDir,rd,mCol,vec3(1.0),0.1, 0.1);
    vec3 c= vec3(0.0);


    if(!intersectTreeP(lightPos2,-lightDir,-invLightDir,bmin,bmax,lightDist-1e-4)) {
        c=calcPtLightCol(pt,nor,lightPos2,vec3(1.0,0.01,0.001),mCol,vec3(1.0),0.2, 0.2);
    } else {
        c=mCol*0.1;
    }

    if(t>=length(lightPos2-ro)) {
        c=mix(c,vec3(3.0),calcFlare(ro,rd,lightPos2,0.05));
    }

    return min(c,1.0);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    float fovy=0.7854;
    float aspect=iResolution.x/iResolution.y;
    //vec2 ms=(iMouse.xy==vec2(0.0))?vec2(0.0):(iMouse.xy/iResolution.xy)*2.0-1.0;

#ifdef SHADRON
    //vec3 viewPos=vec3(0.0);
    vec3 ro=shadron_CameraView[3].xyz*5.0;
    //mat3 viewRot=lookRot(viewYaw,viewPitch);//mat3(1.0);
    mat3 viewRot=transpose(mat3(shadron_CameraView));
    //mat3 viewRot=mat3(shadron_CameraView[0].xyz,shadron_CameraView[1].xyz,shadron_CameraView[2].xyz);
#else

    //mat3 viewRot=lookRot(ms.x*-4.0+3.14,ms.y*1.7);
    //vec3 ro=vec3(2.0,2.0,-3.0);
    //vec3 ro=vec3(1.0,3.0,1.0);
    vec3 ro=viewPos;

    //mat3 viewRot=orbitRot(ms.x*2.0,ms.y*2.0);
    //vec3 ro=viewRot*vec3(0.0,0.0,10.0);
#endif


    vec2 uv=fragCoord/iResolution.xy;
    vec2 scr=uv*2.0-1.0;
    vec3 primary=normalize(vec3(scr.x*aspect,scr.y,-1.0/tan(fovy/2.0)));
    vec3 rd=normalize(viewRot*primary);

    vec3 col=render(ro,rd);

    //col=mix(col,vec3(1.0),step(abs(floor(length(fragCoord-iMouse.xy))-2.0),0.0));

    fragColor=vec4(col,1.0);
}
