require 'test_helper'

class AuthenticationFlowTest < ActionDispatch::IntegrationTest
  
  setup do
    @user = User.first
  end
  
  # ----------------------------------------------------------
  test 'can sign in with valid email and password' do
    get root_path
    assert_response :success
    
    sign_in
    
    # Make sure that the user is sent to the page that lists their plans
    assert_response :success
    assert_select '.main_page_content h1', I18n.t('helpers.project.projects_title')
  end
  
  # ----------------------------------------------------------
  test 'can sign in with shibboleth' do
    
  end
  
  # ----------------------------------------------------------
  test 'can sign out' do
    get root_path
    assert_response :success
    
    sign_in
    
    delete destroy_user_session_path
    
    assert_response :redirect
    follow_redirect!
    
    # Make sure that the user is sent to the page that lists their plans
    assert_response :success
    assert_select '.welcome-message h2', I18n.t('welcome_title')
  end
  
  # ----------------------------------------------------------
  test 'can NOT sign in with an invalid email and/or password' do
    get root_path
    assert_response :success
    
    users = [{email: @user.email, password: 'bAd_pas$word1', remember_me: true},
             {email: 'unknown@institution.org', password: 'password123', remember_me: true}]
    
    users.each do |params|
      post user_session_path, user: params
    
      assert_response :redirect
      follow_redirect!
    
      # Make sure that the user is sent to the page that lists their plans
      assert_response :success
      assert_select '.welcome-message h2', I18n.t('welcome_title')
    end
  end


  private
    # ----------------------------------------------------------
    def sign_in
      post user_session_path, user: {
        email: @user.email, 
        password: 'password123', 
        remember_me: false
      }
    
      # The Devise auth gem will end up performing 2 redirects while generating the user's
      # session and sending them to the main landing page
      2.times do
        assert_response :redirect
        follow_redirect!
      end
    end
end
