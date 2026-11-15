import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart' as crypto;
import 'attachment_files.dart';
import 'workspace_api.dart';

abstract class AttachmentTransport {
  Future<Map<String,dynamic>> upload(String token,Map<String,Object?> file);
  Future<String> download(String token,int task,int attachment,String target);
}

class NativeFileTransfers implements AttachmentTransport {
  Future<void> status(HttpClientResponse response) async {
    final code=response.statusCode;
    if(code==401)throw const ApiFailure(401,'Сессия истекла. Войди снова');
    if(code==429)throw const ApiFailure(429,'Слишком много запросов. Повтори позже');
    if(code<200||code>=300)throw ApiFailure(code,code==422?'Файл не принят: проверь тип, размер и лимит вложений':'Ошибка передачи файла: $code');
  }
  @override
  Future<Map<String,dynamic>> upload(String token,Map<String,Object?> file) async {
    final client=HttpClient()..connectionTimeout=const Duration(seconds:20);
    try {
      return await (() async {
        final saved=Map<String,dynamic>.from(jsonDecode(file['request_json'] as String) as Map);
        final boundary='sovdelo-${saved['operation_uuid']}';
        final prefix=StringBuffer();
        for(final field in ['operation_uuid','name','sha256']) {
          prefix.write('--$boundary\r\nContent-Disposition: form-data; name="$field"\r\n\r\n${saved[field]}\r\n');
        }
        final ext=(file['name'] as String).split('.').last;
        prefix.write('--$boundary\r\nContent-Disposition: form-data; name="file"; filename="file.$ext"\r\nContent-Type: application/octet-stream\r\n\r\n');
        final head=utf8.encode(prefix.toString()), tail=utf8.encode('\r\n--$boundary--\r\n');
        final request=await client.postUrl(WorkspaceApi.origin.resolve('tasks/${saved['task_id']}/attachments'));
        request.followRedirects=false;
        request.headers.set(HttpHeaders.authorizationHeader,'Bearer $token');
        request.headers.set(HttpHeaders.acceptHeader,'application/json');
        request.headers.contentType=ContentType('multipart','form-data',parameters:{'boundary':boundary});
        request.contentLength=head.length+(file['bytes'] as int)+tail.length;
        request.add(head);await request.addStream(File(file['local_path'] as String).openRead());request.add(tail);
        final response=await request.close();await status(response);
        final bytes=<int>[];
        await for(final chunk in response) {if(bytes.length+chunk.length>1024*1024)throw const ApiFailure(0,'Слишком большой ответ');bytes.addAll(chunk);}
        final parsed=jsonDecode(utf8.decode(bytes));
        if(parsed is! Map||parsed['data'] is! Map)throw const ApiFailure(0,'Нет подтверждения загрузки');
        return Map<String,dynamic>.from(parsed['data'] as Map);
      })().timeout(const Duration(seconds:120));
    }on ApiFailure{rethrow;}on FileSystemException{throw ArgumentError('Локальную копию не удалось прочитать');}
    on TimeoutException{throw const ApiFailure(0,'Загрузка не завершилась вовремя. Файл остался в очереди');}
    on SocketException{throw const ApiFailure(0,'Нет соединения. Файл остался в очереди');}
    on HandshakeException{throw const ApiFailure(0,'Не удалось проверить HTTPS');}
    on HttpException{throw const ApiFailure(0,'Передача прервалась. Повтори запрос');}
    on FormatException{throw const ApiFailure(0,'Некорректный ответ сервера');}
    finally{client.close(force:true);}
  }
  @override
  Future<String> download(String token,int task,int attachment,String target) async {
    final client=HttpClient()..connectionTimeout=const Duration(seconds:20);
    try {
      return await (() async {
        final request=await client.getUrl(WorkspaceApi.origin.resolve('tasks/$task/attachments/$attachment'));
        request.followRedirects=false;request.headers.set(HttpHeaders.authorizationHeader,'Bearer $token');
        final response=await request.close();await status(response);
        final expected=response.headers.value('x-file-sha256');
        if(expected==null||!RegExp(r'^[a-f0-9]{64}$').hasMatch(expected))throw const ApiFailure(0,'Сервер не передал контрольную сумму');
        if(response.contentLength>AttachmentFiles.maxBytes)throw const ApiFailure(0,'Файл больше 10 МБ');
        final sink=File(target).openWrite();var count=0;
        try {
          await for(final chunk in response) {count+=chunk.length;if(count>AttachmentFiles.maxBytes)throw const ApiFailure(0,'Файл больше 10 МБ');sink.add(chunk);}
          await sink.flush();
        }finally{await sink.close();}
        if(count<1)throw const ApiFailure(0,'Сервер вернул пустой файл');
        final actual=(await crypto.sha256.bind(File(target).openRead()).first).toString();
        if(actual!=expected)throw const ApiFailure(0,'Контрольная сумма скачанного файла не совпала');
        return actual;
      })().timeout(const Duration(seconds:120));
    }on ApiFailure{rethrow;}on TimeoutException{throw const ApiFailure(0,'Скачивание не завершилось вовремя');}
    on SocketException{throw const ApiFailure(0,'Нет соединения с сервером');}
    on HandshakeException{throw const ApiFailure(0,'Не удалось проверить HTTPS');}
    on HttpException{throw const ApiFailure(0,'Скачивание прервалось');}
    finally{client.close(force:true);}
  }
}
