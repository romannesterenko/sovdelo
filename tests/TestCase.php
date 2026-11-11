<?php
namespace Tests;
use RuntimeException;
abstract class TestCase extends \Illuminate\Foundation\Testing\TestCase
{
 public function createApplication()
 {
  $app=parent::createApplication();
  // Must run before RefreshDatabase can execute any migration.
  $database=$app['config']->get('database.connections.pgsql.database');
  if(!$app->environment('testing') || $app['config']->get('database.default')!=='pgsql' || $database!=='sovdelo_testing' || $app['config']->get('database.connections.pgsql.url')){
   throw new RuntimeException('Тесты остановлены: нужна отдельная PostgreSQL-база sovdelo_testing, APP_ENV=testing и пустой DB_URL. Запуск: bash test.sh');
  }
  return $app;
 }
}
