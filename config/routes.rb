Rails.application.routes.draw do
  resources :posts do
    get :do_word_count, on: :collection
    get :show_word_count, on: :collection
  end
  resources :users

  root 'users#index'
end
