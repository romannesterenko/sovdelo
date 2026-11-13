<?php

use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        $middleware->statefulApi();
        // Import fingerprints must use the exact bytes of the uploaded JSON.
        $middleware->trimStrings(except: ['payload']);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        $exceptions->render(function(\Throwable $e,Request $r){
            if(!$r->is('api/v1','api/v1/*'))return null;
            $details=[];$headers=[];
            if($e instanceof \Illuminate\Validation\ValidationException){$status=422;$details=$e->errors();}
            elseif($e instanceof \Illuminate\Auth\AuthenticationException)$status=401;
            elseif($e instanceof \Illuminate\Auth\Access\AuthorizationException)$status=403;
            elseif($e instanceof \Illuminate\Database\Eloquent\ModelNotFoundException)$status=404;
            elseif($e instanceof \Symfony\Component\HttpKernel\Exception\HttpExceptionInterface){$status=$e->getStatusCode();$headers=$e->getHeaders();}
            else $status=500;
            $codes=[401=>'unauthenticated',403=>'forbidden',404=>'not_found',409=>'conflict',413=>'payload_too_large',422=>'validation_failed',429=>'rate_limited'];
            $messages=[401=>'Требуется действующий токен устройства.',403=>'Недостаточно прав.',404=>'Объект не найден.',409=>'Данные изменились. Обновите их и повторите запрос.',413=>'Слишком большой запрос.',422=>'Проверьте поля запроса.',429=>'Слишком много запросов. Повторите позже.'];
            return response()->json(['error'=>['code'=>$codes[$status]??'server_error','message'=>$messages[$status]??'Не удалось выполнить запрос.','details'=>(object)$details],'meta'=>['api_version'=>'1']],$status,$headers);
        });
        $exceptions->shouldRenderJsonWhen(
            fn (Request $request) => $request->is('api/*') || $request->expectsJson(),
        );
    })->create();
