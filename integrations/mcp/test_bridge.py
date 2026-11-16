import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock

PATH = Path(__file__).with_name('sovdelo_mcp.py')
spec = importlib.util.spec_from_file_location('sovdelo_mcp', PATH)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class BridgeTest(unittest.TestCase):
    def test_initialize_and_read_tools_do_not_call_network(self):
        api = Mock(); server = m.Server(api)
        self.assertEqual(server.handle({'jsonrpc':'2.0','id':0,'method':'tools/list'})['error']['code'], -32002)
        result = server.handle({'jsonrpc':'2.0','id':1,'method':'initialize','params':{'protocolVersion':'2025-06-18'}})
        self.assertEqual(result['result']['protocolVersion'], '2025-06-18')
        self.assertEqual(len(server.handle({'jsonrpc':'2.0','id':2,'method':'tools/list'})['result']['tools']), 6)
        api.request.assert_not_called()

    def test_request_notification_has_no_response(self):
        self.assertIsNone(m.Server(Mock()).handle({'jsonrpc':'2.0','method':'notifications/initialized'}))

    def test_write_repeats_same_idempotency_key_and_body(self):
        api=Mock();args={'title':'Новая','request_key':'c1c1c1c1-1111-4111-8111-111111111111'}
        m.call(api,'sovdelo_create',args);m.call(api,'sovdelo_create',args)
        self.assertEqual(api.request.call_args_list[0],api.request.call_args_list[1])
        self.assertEqual(api.request.call_args.args[3],args['request_key'])

    def test_owner_only_actions_and_foreign_parameters_are_rejected(self):
        api=Mock()
        for args in ({'task_id':1,'action':'accept','expected_version':1,'request_key':'key'},
                     {'task_id':1,'action':'claim','expected_version':1,'request_key':'key','project_id':2}):
            with self.assertRaises(m.ToolError):m.call(api,'sovdelo_action',args)
        api.request.assert_not_called()

    def test_headers_https_uuid_and_no_redirect(self):
        with self.assertRaises(m.ToolError):m.Api('http://example.com','token')
        api=m.Api('https://example.com/api','fake-token');response=Mock()
        response.__enter__=Mock(return_value=response);response.__exit__=Mock(return_value=False)
        response.read.return_value=b'{"data":{"ok":true}}';api.opener=Mock();api.opener.open.return_value=response
        with self.assertRaises(m.ToolError):api.request('tasks','POST',{},'invalid')
        api.opener.open.assert_not_called()
        api.request('tasks','POST',{},'c1c1c1c1-1111-4111-8111-111111111111')
        request=api.opener.open.call_args.args[0]
        self.assertEqual(request.get_header('Authorization'),'Bearer fake-token')
        self.assertEqual(request.get_header('Idempotency-key'),'c1c1c1c1-1111-4111-8111-111111111111')
        with self.assertRaises(m.ToolError):m.NoRedirect().redirect_request(request,None,302,'',{},'https://other.example')

    def test_api_error_is_contained_and_does_not_expose_token(self):
        api=Mock();api.request.side_effect=m.ToolError('Доступ истёк или отозван.')
        server=m.Server(api);server.handle({'jsonrpc':'2.0','id':1,'method':'initialize'})
        r=server.handle({'jsonrpc':'2.0','id':2,'method':'tools/call','params':{'name':'sovdelo_context'}})
        self.assertTrue(r['result']['isError']);self.assertNotIn('fake-token',json.dumps(r))

    def test_config_permissions_and_stdio_process(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'agent.json';path.write_text(json.dumps({'url':'https://example.com/api','token':'fake-secret'}));path.chmod(0o644)
            with self.assertRaises(m.ToolError):m.load(path)
            path.chmod(0o600)
            request='\n'.join(json.dumps(r) for r in [
                {'jsonrpc':'2.0','id':1,'method':'initialize','params':{'protocolVersion':'2025-06-18'}},
                {'jsonrpc':'2.0','method':'notifications/initialized'},
                {'jsonrpc':'2.0','id':2,'method':'tools/list'}])+'\n'
            process=subprocess.run([sys.executable,str(PATH),'--config',str(path)],input=request,text=True,capture_output=True,check=True)
            rows=[json.loads(line) for line in process.stdout.splitlines()]
            self.assertEqual([r['id'] for r in rows],[1,2]);self.assertEqual(process.stderr,'')
            self.assertNotIn('fake-secret',process.stdout)

if __name__=='__main__':unittest.main()
