"""CPA child-process transport hint. Keep normal DNS results, SNI and TLS verification."""
import os,socket
_host=os.environ.get('CPA_IPV6_HOST','').lower().rstrip('.')
_original=socket.getaddrinfo
if _host:
 def _ordered(host,*args,**kwargs):
  result=_original(host,*args,**kwargs)
  name=host.decode('ascii') if isinstance(host,bytes) else str(host)
  if name.lower().rstrip('.')==_host:
   return sorted(result,key=lambda entry:entry[0]!=socket.AF_INET6)
  return result
 socket.getaddrinfo=_ordered
