# Controller Expert Quick Reference

## Controller Template

```ruby
class ResourcesController < ApplicationController
  include HipaaAuditable

  before_action :authenticate_user!
  before_action :set_resource, only: [:show, :edit, :update, :destroy]

  def index
    authorize Resource
    @q = policy_scope(Resource).ransack(params[:q])
    @pagy, @resources = pagy(@q.result(distinct: true).order(created_at: :desc))
  end

  def show
    authorize @resource
    log_hipaa_access(@resource)
  end

  def new
    @resource = Resource.new
    authorize @resource
  end

  def create
    @resource = Resource.new(resource_params)
    authorize @resource

    if @resource.save
      redirect_to @resource, notice: 'Created successfully.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @resource
  end

  def update
    authorize @resource

    if @resource.update(resource_params)
      redirect_to @resource, notice: 'Updated successfully.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @resource
    @resource.soft_delete
    redirect_to resources_path, notice: 'Deleted.', status: :see_other
  end

  private

  def set_resource
    @resource = Resource.find(params[:id])
  end

  def resource_params
    params.require(:resource).permit(:attr1, :attr2)
  end
end
```

## Authorization Patterns

```ruby
# Collection actions - authorize the class
authorize Resource
@resources = policy_scope(Resource)

# Instance actions - authorize the record
authorize @resource

# Custom action with explicit policy method
authorize @resource, :custom_action?

# Ensure authorization was called
after_action :verify_authorized
after_action :verify_policy_scoped, only: :index
```

## Response Formats

```ruby
respond_to do |format|
  format.html { redirect_to @resource }
  format.json { render json: resource_json(@resource) }
  format.turbo_stream do
    render turbo_stream: [
      turbo_stream.append('list', partial: 'item', locals: { item: @item }),
      turbo_stream.replace('flash', partial: 'shared/flash')
    ]
  end
end
```

## JSON Response Patterns

```ruby
# Success
render json: { data: @resources }, status: :ok
render json: resource_json(@resource), status: :created

# Error
render json: { errors: @resource.errors.full_messages }, status: :unprocessable_entity
render json: { error: 'Not found' }, status: :not_found
```

## Service Integration

```ruby
result = MyService.call(params: resource_params, user: current_user)

if result.success?
  @resource = result.data[:resource]
  redirect_to @resource
else
  flash.now[:alert] = result.error
  render :new, status: :unprocessable_entity
end
```

## HIPAA Logging

```ruby
include HipaaAuditable

log_hipaa_access(@client)
log_hipaa_access(@document, action_type: 'export')
log_hipaa_access(@record, action_type: 'download')
```

## Pagination

```ruby
@pagy, @resources = pagy(
  policy_scope(Resource).order(created_at: :desc),
  items: 25
)

# JSON pagination
{
  current_page: @pagy.page,
  total_pages: @pagy.pages,
  total_count: @pagy.count
}
```

## Strong Parameters

```ruby
def resource_params
  params.require(:resource).permit(
    :name,
    :status,
    items_attributes: [:id, :name, :_destroy],
    tag_ids: []
  )
end
```

## Turbo Stream Actions

```ruby
turbo_stream.append(target, partial: 'item', locals: { item: @item })
turbo_stream.prepend(target, partial: 'item', locals: { item: @item })
turbo_stream.replace(target, partial: 'item', locals: { item: @item })
turbo_stream.update(target, html: 'content')
turbo_stream.remove(target)
```

## Error Handling

```ruby
def render_error(message, status)
  respond_to do |format|
    format.html { redirect_back fallback_location: root_path, alert: message }
    format.json { render json: { error: message }, status: status }
  end
end

# Exception rescue
rescue ActiveRecord::RecordNotFound
  render json: { error: 'Not found' }, status: :not_found
```

## Current User Helpers

```ruby
current_user                # Logged in user
current_organization        # Current tenant
current_user.has_role?(:admin)
current_user.has_role?(:therapist, current_organization)
```

## Custom Actions

```ruby
# routes.rb
resources :resources do
  member do
    post :archive
    post :restore
  end
  collection do
    get :search
    get :dashboard
  end
end
```

## Redirect Patterns

```ruby
redirect_to @resource, notice: 'Success.'
redirect_to resources_path, status: :see_other  # After DELETE
redirect_back fallback_location: root_path, alert: 'Error.'
redirect_to request.referer || resources_path
```

## Namespaced Controllers

```ruby
# app/controllers/staff/resources_controller.rb
module Staff
  class ResourcesController < ApplicationController
    # Staff-specific logic
  end
end

# app/controllers/api/resources_controller.rb
module Api
  class ResourcesController < Api::BaseController
    # API-specific logic
  end
end
```

## Checklist

- [ ] `authenticate_user!` before_action
- [ ] `authorize` called for all actions
- [ ] `policy_scope` used for collections
- [ ] `log_hipaa_access` for PHI controllers
- [ ] Strong parameters defined
- [ ] Multiple response formats (HTML, JSON, Turbo)
- [ ] Error handling with user-friendly messages
- [ ] `status: :see_other` for DELETE redirects
- [ ] Eager loading to prevent N+1 queries
