import test from 'node:test';
import assert from 'node:assert/strict';
import {createHandler, parseProduct} from './handler.mjs';
const env=name=>({SUPABASE_URL:'https://test.supabase.co',SUPABASE_ANON_KEY:'public-key',GROQ_API_KEY:'server-key'})[name];
const image='/9j/'+ 'AAAA'.repeat(40);
const req=(body,auth=true)=>new Request('https://example.com',{method:'POST',headers:auth?{Authorization:'Bearer token'}:{},body:JSON.stringify(body)});
test('auth and consent are required before image AI calls',async()=>{
 const calls=[]; const handler=createHandler(env,async(url)=>{calls.push(url);return Response.json({id:'u'});});
 assert.equal((await handler(req({image,ai_consent:true},false))).status,401);
 assert.equal((await handler(req({image}))).status,400);
 assert.equal(calls.filter(x=>x.includes('groq')).length,0);
});
test('quota fails closed and product output never includes a price',async()=>{
 const calls=[];const handler=createHandler(env,async(url,options)=>{
 calls.push(url);
 if(url.endsWith('/user'))return Response.json({id:'u'});
 if(url.includes('consume_receipt_scan'))return Response.json(true);
 const sent=JSON.parse(options.body);assert.ok(sent.messages[1].content[1].image_url.url.startsWith('data:image/jpeg;base64,'));
 return Response.json({choices:[{message:{content:JSON.stringify({is_product:true,name:'Shampoo',category:'groceries',price:999})}}]});
 });
 const response=await handler(req({image,ai_consent:true}));assert.equal(response.status,200);
 assert.deepEqual(await response.json(),{is_product:true,name:'Shampoo',category:'groceries'});
 const denied=createHandler(env,async url=>url.endsWith('/user')?Response.json({id:'u'}):Response.json(false));
 assert.equal((await denied(req({image,ai_consent:true}))).status,429);
});
test('invalid categories and malformed data fail validation',()=>{
 assert.equal(parseProduct({is_product:true,name:'Phone',category:'salary'}).category,'other');
 assert.equal(parseProduct({is_product:true,name:'Unknown item'}).category,'other');
 assert.throws(()=>parseProduct({is_product:true,name:123,category:'shopping'}));
 assert.deepEqual(parseProduct({is_product:false,name:'',category:'other'}),{is_product:false,name:'',category:'other'});
});
