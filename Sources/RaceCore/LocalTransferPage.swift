import Foundation

enum LocalTransferPage {
  static let html = """
  <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Send files to OpenRaceRender</title>
  <style>body{font:17px system-ui;max-width:38em;margin:3em auto;padding:0 1em;background:#101722;color:#e7eef7}button,input{font:inherit;margin:1em 0;padding:.7em}button{background:#86e2c4;border:0;border-radius:.4em}progress{width:100%}#status{white-space:pre-wrap}</style>
  <h1>Send files to OpenRaceRender</h1>
  <p>Select exported telemetry and its video files. Keep this page open until the transfer finishes. The Mac will let you review and import the received files.</p>
  <input id="files" type="file" multiple><br><button id="send">Send selected files</button>
  <progress id="progress" value="0" max="1"></progress><p id="status" role="status">Choose files to begin.</p>
  <script>
  const token=new URLSearchParams(location.search).get('token'),status=document.querySelector('#status'),button=document.querySelector('#send'),progress=document.querySelector('#progress');
  button.onclick=async()=>{const files=[...document.querySelector('#files').files];if(!files.length)return;button.disabled=true;try{
    for(let i=0;i<files.length;i++){status.textContent='Sending '+files[i].name+' ('+(i+1)+'/'+files.length+')';
      const response=await fetch('/upload?token='+encodeURIComponent(token)+'&name='+encodeURIComponent(files[i].name),{method:'PUT',body:files[i]});
      if(!response.ok)throw new Error(await response.text());progress.value=(i+1)/files.length;}
    const response=await fetch('/finish?token='+encodeURIComponent(token),{method:'POST'});if(!response.ok)throw new Error(await response.text());
    status.textContent='Transfer complete. Review and import the files on your Mac.';
  }catch(error){status.textContent=error.message+' Stop and restart receiving on the Mac before retrying.';button.disabled=false;}};
  </script>
  """
}
