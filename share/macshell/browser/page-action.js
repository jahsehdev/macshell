if (!window.__macshellToolsInstalled) {
  window.__macshellToolsInstalled=true;
  browser.runtime.onMessage.addListener(message=>{
    if(!message.macshellPageAction)return;
    let style=document.getElementById('macshell-page-style');
    if(!style){style=document.createElement('style');style.id='macshell-page-style';document.documentElement.append(style);}
    const rules={
      readable:'body{max-width:900px!important;margin:24px auto!important;padding:24px!important;line-height:1.7!important}p{font-size:18px!important}',
      'large-text':'body,p,li,article{font-size:20px!important;line-height:1.6!important}',
      focus:'aside,nav,[role="navigation"],[role="complementary"],iframe{display:none!important}main,article{max-width:900px!important;margin:auto!important}',
      reset:''
    };
    if(Object.hasOwn(rules,message.macshellPageAction))style.textContent=rules[message.macshellPageAction];
  });
}
