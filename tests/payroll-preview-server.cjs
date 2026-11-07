/* Pratinjau lokal untuk QA: HTML/JS produksi + RPC SQL asli di PostgreSQL WASM.
 * Autentikasi diganti fixture di localhost. Jangan deploy/menjalankan sebagai server publik. */
const http=require('node:http'),fs=require('node:fs'),path=require('node:path');
const {PGlite}=require(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const root=path.resolve(__dirname,'..'), port=Number(process.env.PAYROLL_TEST_PORT || 8765);
const owner='00000000-0000-4000-8000-000000000001', employeeUser='00000000-0000-4000-8000-000000000002';
const employee='00000000-0000-4000-8000-000000000012';
const routes={
  owner_staff_list:[], owner_cash_advances:[['p_month','date']],
  attendance_calendar:[['p_bulan','date']], attendance_report:[['p_bulan','date']],
  owner_set_employee_payroll:[['p_id','uuid'],['p_patch','jsonb']],
  my_cash_advances:[],request_cash_advance:[['p_amount','numeric'],['p_reason','text'],['p_request_key','uuid']],
  decide_cash_advance:[['p_id','uuid'],['p_approve','boolean'],['p_note','text']],
  disburse_cash_advance:[['p_id','uuid'],['p_reference','text']],
  owner_payroll_data:[['p_id','uuid'],['p_month','date']],
  owner_upsert_karyawan:[['p_id','uuid'],['p_nama','text'],['p_telepon','text'],['p_jabatan','text'],['p_ikut_pos','boolean'],['p_aktif','boolean'],['p_jam_masuk','time'],['p_jam_pulang','time'],['p_payroll','jsonb']]
};
async function start(){
 const db=new PGlite();
 await db.exec(fs.readFileSync(path.join(__dirname,'fixtures/payroll-base.sql'),'utf8'));
 for(const f of ['supabase_migration_23_kalender_mangkir.sql','supabase_migration_62_jadwal_penggajian.sql','supabase_migration_63_kasbon_slip_gaji.sql']) await db.exec(fs.readFileSync(path.join(root,f),'utf8'));
 await db.query("SELECT set_config('test.today','2026-11-07',false)");
 await db.query("INSERT INTO auth.users VALUES ($1,'owner@test.invalid'),($2,'employee@test.invalid')",[owner,employeeUser]);
 await db.query("INSERT INTO profiles VALUES ($1,'owner'),($2,'capster')",[owner,employeeUser]);
 await db.query("INSERT INTO capsters(id,name,auth_user_id,jabatan,jam_masuk,jam_pulang) VALUES($1,'Cena',$2,'Kapster','09:00','17:00')",[employee,employeeUser]);
 await db.query("SELECT set_config('request.jwt.claim.sub',$1,false)",[owner]);
 await db.query('SELECT owner_set_employee_payroll($1,$2)',[employee,JSON.stringify({working_days:[1,2,3,4,5],base_salary:3000000,bank_name:'SeaBank',bank_account_number:'001234567890',bank_account_holder:'Nama Uji'})]);
 await db.query("INSERT INTO attendances(capster_id,business_date,check_in_time,check_out_time,status) SELECT $1,d::DATE,d+interval '2 hours',d+interval '10 hours','hadir' FROM generate_series('2026-11-02'::TIMESTAMP,'2026-11-06',interval '1 day') d",[employee]);
 await db.query("INSERT INTO attendances(capster_id,business_date,check_in_time,check_out_time,status) SELECT $1,d::DATE,d+interval '2 hours',d+interval '10 hours 54 minutes 36 seconds','hadir' FROM generate_series('2026-09-01'::TIMESTAMP,'2026-09-23',interval '1 day') d",[employee]);
 let queue=Promise.resolve();
 const server=http.createServer(async(req,res)=>{
  const url=new URL(req.url,'http://127.0.0.1');
  if(url.pathname==='/test-rpc' && req.method==='POST'){
   let body='';for await(const chunk of req){body+=chunk;if(body.length>100000){res.writeHead(413).end();return;}}
   const respond=async()=>{
    try{
     const {name,args={}}=JSON.parse(body), role=url.searchParams.get('role');
     if(!(name in routes)){res.setHeader('Content-Type','application/json');res.end(JSON.stringify({data:[],error:null}));return;}
     await db.exec('RESET ROLE');await db.query("SELECT set_config('request.jwt.claim.sub',$1,false)",[role==='employee'?employeeUser:owner]);await db.exec('SET ROLE authenticated');
     const params=routes[name],table=['owner_staff_list','attendance_calendar','attendance_report','owner_upsert_karyawan'].includes(name);
     const sql='SELECT '+(table?'* FROM ':'')+name+'('+params.map(([key,type],i)=>'$'+(i+1)+'::'+type).join(',')+')';
     const result=await db.query(sql,params.map(([key,type])=>type==='jsonb'?JSON.stringify(args[key]):args[key]??null));
     const data=table?result.rows:result.rows[0][name];
     res.setHeader('Content-Type','application/json');res.end(JSON.stringify({data,error:null}));
    }catch(error){res.setHeader('Content-Type','application/json');res.end(JSON.stringify({data:null,error:{message:error.message}}));}
   };queue=queue.then(respond,respond);return;
  }
  if(url.pathname==='/test-sb.js'){
   const role=url.searchParams.get('role');
   res.setHeader('Content-Type','text/javascript');res.end(`
     const SBConn={online:true};const sbJakartaToday=()=> '2026-11-07';
     const sbSignOut=()=>{};const sbRenderConnPill=()=>{};
     const sbRequireAuth=async()=>({profile:{role:'owner',full_name:'Owner QA'}});
     const sb={rpc:async(name,args={})=>(await fetch('/test-rpc?role=${role}',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name,args})})).json(),
       storage:{from:()=>({getPublicUrl:()=>({data:{publicUrl:''}})})},
       from:()=>{const chain=new Proxy({}, {get:(t,k)=>k==='then'?r=>Promise.resolve({data:[],error:null}).then(r):()=>chain});return chain;}};
   `);return;
  }
  const file=path.resolve(root,'.'+decodeURIComponent(url.pathname==='/'?'/rekap.html':url.pathname));
  if(!file.startsWith(root+path.sep) || !fs.existsSync(file) || fs.statSync(file).isDirectory()){res.writeHead(404).end();return;}
  let data=fs.readFileSync(file);
  if(['rekap.html','capster.html'].includes(path.basename(file))){
   const isOwner=path.basename(file)==='rekap.html';let html=data.toString();
   html=html.replace('<script src="sb-app.js"></script>','<script src="/test-sb.js?role='+(isOwner?'owner':'employee')+'"></script>');
   const a=html.lastIndexOf('(async function boot() {'),b=html.indexOf('})();',a)+5;
   const boot=isOwner?`(async function boot(){document.getElementById('ownerName').textContent='Owner QA';await muatKelolaAkun();pasangPemilihBulan();await loadKalender();await loadAbsensi();})();`:
    `(async function boot(){meCapster={id:'${employee}',name:'Cena',jabatan:'Kapster'};document.getElementById('mainArea').hidden=false;document.getElementById('capsterName').textContent='Cena';await EmployeeCash.load();})();`;
   html=html.slice(0,a)+boot+html.slice(b);data=Buffer.from(html);
  }
  const ext=path.extname(file);res.setHeader('Content-Type',({'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.png':'image/png','.webp':'image/webp'})[ext]||'application/octet-stream');res.end(data);
 });
 server.listen(port,'127.0.0.1',()=>console.log('Payroll QA: http://127.0.0.1:'+port+'/rekap.html#karyawan (fixture only)'));
}
start().catch(e=>{console.error(e.message);process.exitCode=1;});
