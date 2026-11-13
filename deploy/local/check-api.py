#!/usr/bin/env python3
"""Interactive read-only API smoke check; never saves or prints its temporary token."""
import argparse,getpass,json,urllib.request,urllib.error,urllib.parse,sys
p=argparse.ArgumentParser();p.add_argument('--url',default='https://xn--b1aedylep.xn--p1ai');args=p.parse_args()
u=urllib.parse.urlsplit(args.url)
if u.scheme!='https' and not(u.scheme=='http' and u.hostname in ['127.0.0.1','localhost']):raise SystemExit('Используйте HTTPS или локальный адрес.')
if u.username or u.password or u.query or u.fragment:raise SystemExit('Некорректный адрес API')
base=args.url.rstrip('/')+'/api/v1';token=None
class ApiError(Exception):pass
def request(path,method='GET',body=None):
 headers={'Accept':'application/json','Content-Type':'application/json'}
 if token:headers['Authorization']='Bearer '+token
 req=urllib.request.Request(base+path,data=json.dumps(body).encode() if body is not None else None,headers=headers,method=method)
 try:
  with urllib.request.urlopen(req,timeout=30) as response:return json.load(response)
 except urllib.error.HTTPError as e:
  try:d=json.load(e).get('error',{});message=d.get('message','Ошибка API')
  except (ValueError,AttributeError):message='Ошибка HTTP'
  raise ApiError(str(e.code)+': '+message) from None
try:
 email=input('Email аккаунта СовДела: ').strip();password=getpass.getpass('Пароль (не отображается): ')
 d=request('/auth/token','POST',{'email':email,'password':password,'device_name':'Временная проверка API','access':'read'})
 password='';token=d['data']['token']
 request('/me');projects=request('/projects?per_page=1');tasks=request('/tasks?per_page=1')
 print('API v1 работает. Проектов: '+str(projects['meta']['total'])+', активных задач: '+str(tasks['meta']['total']))
except (ApiError,urllib.error.URLError,ValueError,KeyError) as e:
 print('Проверка не завершена: '+str(e),file=sys.stderr);sys.exit_code=1
finally:
 if token:
  try:request('/auth/token','DELETE');print('Временный токен отозван.')
  except (ApiError,urllib.error.URLError):print('Не удалось отозвать токен по сети: отзовите «Временная проверка API» в профиле.',file=sys.stderr);sys.exit_code=1
if getattr(sys,'exit_code',0):raise SystemExit(1)
