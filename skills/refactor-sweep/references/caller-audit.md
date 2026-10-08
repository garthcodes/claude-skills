# Caller audit

A refactor breaks production through the caller nobody listed. Rails reaches code in ways a plain `grep ClassName app` misses, and the app also has code that runs outside the app: runbooks and skills that call services from `bin/rails runner` scripts in production. This file is the checklist for finding every caller and the table format they go in.

Search `$WT`, never the main checkout. Record what you searched, so the cold reviewer can see the audit's edges.

## Searches for every kind

Run each for the moved class name, every moved method name, and (for callbacks) the model:

```bash
cd "$WT"
grep -rn "ClassName\|class_name_snake\|:method_name\|\"method_name\"\|'method_name'" \
  app lib config db/seeds* script spec/support .claude/skills docs --include='*' | grep -v '^spec/refactor_locks'
```

Then the indirect reach, one by one:

- **Metaprogramming**: `send(`, `public_send(`, `try(`, `constantize`, `safe_constantize`, `delegate … to:`, `method(:name)`, callbacks named by symbol, `policy_class`, `"#{…}Service"` string building.
- **Jobs and schedules**: `config/recurring.yml`, `config/queue.yml`, `set(wait…).perform_later` sites, `ApplicationJob` hooks (`on_discard`, `honeybadger_context`).
- **Admin**: `app/avo/` resources, actions, filters and cards (they save records and call services outside controllers).
- **Rake and runbooks**: `lib/tasks/**/*.rake`, `script/`, `tmp/` files committed to git, `docs/*.md` runbooks, and `.claude/skills/*/` (several skills pipe Ruby into `bin/prod-read` or hand the user `bin/rails runner` scripts that call services by name: data-import runbooks, claim-status runbooks, `/stedi-billing-expert`, …).
- **Seeds and imports**: `db/seeds/`, the legacy-system import services (they often set flags such as `imported` to suppress callbacks on purpose).
- **Views and components** for model methods: `app/views`, `app/components`, helpers, mailer templates, `as_json`/serializers.
- **JavaScript** for routes: `app/javascript` (fetch URLs, `data-*-url-value`), and email/SMS templates that embed URLs (`*_url` helpers).
- **Specs** that call the moved code: they're callers too, and the ones asserting on old structure get rewritten (Step 6).

## Kind-specific checks

### callback
List every way the model's row is written with the attributes the callback's condition watches:

- `save`/`update`/`update!`/`create`/`create!` on the model, and on its parents with `accepts_nested_attributes_for` (the child's callbacks fire inside the parent's save);
- `update_column(s)`, `update_all`, `insert_all`, `upsert_all`, `delete_all`, `touch`: these **skip** callbacks today. Their row says "not fired before, not fired after", unless the plan deliberately changes that (it shouldn't);
- `destroy`/soft delete: on SoftDeletable models `destroy` is redirected to `soft_delete` and destroy callbacks don't fire (root CLAUDE.md); check which lifecycle the callback really hooks;
- recurring-series and bulk updaters that loop over records;
- callbacks of *other* models that save this one (cascades);
- the condition itself (`saved_change_to_status?`, `previous_changes`): the service must see the same change information, so it has to be called with the old values or right after the save in the same request.

### model_logic / callable
- Every call site of the method or class, plus `.call` via `Callable`'s class method (`Foo.call(...)` and `Foo.new(...).call`);
- subclasses (`< FooService`) and modules that include it;
- `Result` consumers: callers reading `result.data[:key]` will break if the data shape changes, so list each key read.

### route
- Every `*_path`/`*_url` helper use (`grep -rn "approve_note_path\|approve_note_url"`), `form_with url:`, `button_to`, Turbo Stream targets, JS fetches, mailer/SMS links, and links that might live **outside** the app (emails already sent, bookmarks, portal links). If the old URL can be in someone's inbox, it redirects; it isn't removed.

### unique_index
- Duplicate rows in production: `bin/prod-sql -c "select count(*) from (select <cols> from <table> group by <cols> having count(*) > 1) d"` (count only);
- code that relies on creating the duplicate (find_or_create races, imports).

## The table

```markdown
| # | Caller (file:line) | Path | Triggers today? | After the change | Lock example |
|---|---|---|---|---|---|
| 1 | app/controllers/staff/appointments_controller.rb:88 | update (reschedule) | yes: push job | calls AppointmentCalendarSync#push | appointments_controller_spec.rb:12 |
| 2 | app/services/recurring_series_updater.rb:140 | update_all on series | no (skips callbacks) | no (unchanged) | — |
| 3 | app/services/legacy_import/import_appointments_service.rb:61 | create with imported: true | no (guard) | no (unchanged) | import_spec.rb:5 |
| 4 | .claude/skills/<import-skill>/… runner script | Appointment.create! | yes | **calls service** (script updated) | — (script) |
```

Every "Triggers today? yes" row needs a matching "After" that still triggers, or a **Decision** line in the PR. Every row with a code path the specs can reach needs a lock example, or a note on why not ("runbook script, verified by reading").

## Searched

End the audit file with the searches you ran and anything you couldn't check (e.g. "links in sent emails: can't be enumerated; old route kept as redirect"). The cold reviewer reads this to look past the audit's edges.
