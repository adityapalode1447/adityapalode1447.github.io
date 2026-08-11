const canvas=document.getElementById('space');
const ctx=canvas.getContext('2d');
let w=0,h=0,dpr=1,stars=[],shooters=[],mouse={x:0,y:0},target={x:0,y:0};

function resize(){
  dpr=Math.min(devicePixelRatio||1,2);
  w=innerWidth; h=innerHeight;
  canvas.width=w*dpr; canvas.height=h*dpr;
  canvas.style.width=w+'px'; canvas.style.height=h+'px';
  ctx.setTransform(dpr,0,0,dpr,0,0);
  const count=Math.min(520,Math.max(220,Math.floor(w*h/2800)));
  stars=Array.from({length:count},()=>({
    x:(Math.random()-.5)*w*1.7,y:(Math.random()-.5)*h*1.7,
    z:Math.random()*1, p:Math.random(), size:Math.random()*1.7+.15,
    hue:Math.random()<.12?190:Math.random()<.08?275:215
  }));
}
addEventListener('resize',resize);
addEventListener('mousemove',e=>{target.x=(e.clientX/w-.5)*2;target.y=(e.clientY/h-.5)*2});
resize();

function starfield(){
  ctx.clearRect(0,0,w,h);
  mouse.x+=(target.x-mouse.x)*.035; mouse.y+=(target.y-mouse.y)*.035;

  const cx=w/2+mouse.x*18, cy=h/2+mouse.y*18;
  for(const s of stars){
    s.p+=.0012+s.size*.00035;
    if(s.p>1)s.p=0;
    const depth=.15+s.z*1.2;
    const x=cx+s.x*depth;
    const y=cy+s.y*depth;
    if(x<-40||x>w+40||y<-40||y>h+40) continue;
    const tw=.35+.65*Math.sin((s.p*30)+(s.x*.01));
    ctx.fillStyle=`hsla(${s.hue},90%,${78+s.z*15}%,${(.25+s.z*.65)*tw})`;
    ctx.beginPath();ctx.arc(x,y,s.size*(.45+s.z*1.5),0,Math.PI*2);ctx.fill();
    if(s.z>.82){
      ctx.strokeStyle=`hsla(${s.hue},100%,80%,.12)`;
      ctx.lineWidth=.6;ctx.beginPath();ctx.moveTo(x,y);ctx.lineTo(x-s.size*5,y-s.size*5);ctx.stroke();
    }
  }

  if(Math.random()<.008) shooters.push({
    x:Math.random()*w,y:Math.random()*h*.55,
    vx:8+Math.random()*7,vy:3+Math.random()*4,life:0,max:25+Math.random()*25
  });
  shooters=shooters.filter(s=>{
    s.x+=s.vx;s.y+=s.vy;s.life++;
    const a=1-s.life/s.max;
    const grad=ctx.createLinearGradient(s.x-s.vx*6,s.y-s.vy*6,s.x,s.y);
    grad.addColorStop(0,'rgba(102,232,255,0)');
    grad.addColorStop(1,`rgba(220,250,255,${a*.9})`);
    ctx.strokeStyle=grad;ctx.lineWidth=1.5;
    ctx.beginPath();ctx.moveTo(s.x-s.vx*6,s.y-s.vy*6);ctx.lineTo(s.x,s.y);ctx.stroke();
    return s.life<s.max;
  });
  requestAnimationFrame(starfield);
}
starfield();

function menu(){document.querySelector('nav').classList.toggle('open')}


function openCertificate(image,title,provider){
  const modal=document.getElementById('certificateModal');
  const img=document.getElementById('certModalImage');
  document.getElementById('certModalTitle').textContent=title;
  document.getElementById('certModalProvider').textContent='Issued by '+provider;
  img.src=image;
  modal.classList.add('show');
  modal.setAttribute('aria-hidden','false');
  document.body.style.overflow='hidden';
}
function closeCertificate(e){
  if(e && e.target!==e.currentTarget) return;
  const modal=document.getElementById('certificateModal');
  modal.classList.remove('show');
  modal.setAttribute('aria-hidden','true');
  document.body.style.overflow='';
}
document.addEventListener('keydown',e=>{if(e.key==='Escape')closeCertificate()});

// Show confirmation after FormSubmit redirects back to the contact page.
document.addEventListener('DOMContentLoaded',()=>{
  if(new URLSearchParams(location.search).get('sent')==='1'){
    const form=document.querySelector('.contact-form');
    if(form){
      const note=document.createElement('div');
      note.className='form-success';
      note.textContent='✓ Message sent successfully. I’ll get it on Gmail.';
      form.prepend(note);
      history.replaceState({},'',location.pathname);
    }
  }
});
