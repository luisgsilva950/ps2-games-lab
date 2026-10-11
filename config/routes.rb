Rails.application.routes.draw do
 root "game_images#index"
 resources :game_images, only: %i[index create show] do
  get :events, on: :member, controller: "game_events", action: :show
  resources :messages, only: :create
  resource :launch, only: :create, controller: "launches"
 end
 get "up" => "rails/health#show", as: :rails_health_check
end
