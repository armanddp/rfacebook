# Copyright (c) 2007, Matt Pizzimenti (www.livelearncode.com)
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without modification,
# are permitted provided that the following conditions are met:
# 
# Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
# 
# Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
# 
# Neither the name of the original author nor the names of contributors
# may be used to endorse or promote products derived from this software
# without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

require File.dirname(__FILE__) + "/test_helper"
require "test/unit"
require "rubygems"
require "mocha"

class ControllerTest < Test::Unit::TestCase
    
  def test_before_filters_are_present
    assert @controller.respond_to?(:require_facebook_login)
    assert @controller.respond_to?(:require_facebook_install)
    assert @controller.respond_to?(:handle_facebook_login)
  end
  
  def test_facebook_helpers_are_present
    assert @controller.respond_to?(:in_facebook_canvas?)
    assert @controller.respond_to?(:in_facebook_frame?)
    assert @controller.respond_to?(:in_mock_ajax?)
    assert @controller.respond_to?(:in_external_app?)
    assert @controller.respond_to?(:added_facebook_application?)
    
    assert @controller.respond_to?(:facebook_debug_panel)
    assert @controller.respond_to?(:render_with_facebook_debug_panel)
  end
  
  def test_overrides_are_present
    assert_rfacebook_overrides_method(@controller, :url_for)
    assert_rfacebook_overrides_method(@controller, :redirect_to)
  end
  
  def test_unactivated_fbsession_raises_errors
    post :index
    assert_raise(RFacebook::FacebookSession::NotActivatedStandardError){@controller.fbsession.friends_get}
  end
  
  def test_should_detect_user_has_added_app
    
    # test adding app
    post :index, {:fb_sig_added => 1}
    assert @controller.added_facebook_application?, "Should be installed"
    
    # test not adding app
    @controller.stub_fbparams
    post :index
    assert !@controller.added_facebook_application?, "Should not be installed"
    
  end
  
  def test_should_detect_user_in_canvas
    
    # test adding app
    post :index, {:fb_sig_in_canvas => 1}
    assert @controller.in_facebook_canvas?, "Should be in canvas"
    
    # test not adding app
    post :index
    assert !@controller.in_facebook_canvas?, "Should not be in canvas"
    
  end
  
  def test_should_detect_user_in_iframe
    
    # test adding app
    post :index, {:fb_sig_in_iframe => 1}
    assert @controller.in_facebook_frame?, "Should be in iframe"
    
    # test not adding app
    post :index
    assert !@controller.in_facebook_frame?, "Should not be in iframe"
    
  end
    
  def test_canvas_authentication_succeeds
    @controller.simulate_inside_canvas
    post :index
    assert @controller.fbsession.is_ready?
    assert_equal "viewing index", @response.body
  end
  
  def test_fbsession_exists_and_is_correct
    @controller.stub_fbparams
    post :index
    assert_kind_of RFacebook::FacebookWebSession, @controller.fbsession
  end
  
  def test_should_redirect_for_unauthenticated_user_in_external_site
    post :index
    assert_redirected_to "http://www.facebook.com/login.php?v=1.0&api_key=#{@controller.facebook_api_key}"
  end
  
  def test_should_redirect_for_unauthenticated_user_in_canvas
    post :index, {:fb_sig_in_canvas => 1}
    assert !@controller.fbsession.is_ready?, "Session should be invalid since the user hasn't logged in."
    assert_equal "<fb:redirect url=\"http://www.facebook.com/login.php?v=1.0&api_key=#{@controller.facebook_api_key}&canvas=true\" />", @response.body
  end
  
  def test_redirect_when_not_in_canvas
    post :doredirect, {:redirect_url => "http://www.dummy.com"}
    assert_redirected_to "http://www.dummy.com"
  end
  
  def test_redirect_when_in_canvas
    @controller.simulate_inside_canvas
    post :doredirect, {:redirect_url => "http://www.dummy.com"}
    assert_equal "<fb:redirect url=\"http://www.dummy.com\" />", @response.body
  end
  
  def test_should_have_valid_session_when_auth_token_is_set_for_external_app
    RFacebook::FacebookWebSession.any_instance.expects(:post_request).returns @dummy_auth_getSession_response1
    post :index, {:auth_token => "abc123"}
    assert @controller.fbsession.is_ready?
    assert_equal "finished facebook login", @response.body
  end
  
  def test_should_grab_new_session_when_different_but_valid_auth_token_is_given_for_external_app
    
    # first request
    RFacebook::FacebookWebSession.any_instance.expects(:post_request).returns @dummy_auth_getSession_response1
    post :index, {:auth_token => "abc123"}
    assert @controller.fbsession.is_ready?
    assert_equal "finished facebook login", @response.body
    
    firstSessionKey = @controller.fbsession.session_key
    assert_equal "5f34e11bfb97c762e439e6a5-8055", firstSessionKey
    
    # second (valid) request
    RFacebook::FacebookWebSession.any_instance.expects(:post_request).returns @dummy_auth_getSession_response2
    post :index, {:auth_token => "xyz987"}
    assert @controller.fbsession.is_ready?
    assert_equal "finished facebook login", @response.body
    
    secondSessionKey = @controller.fbsession.session_key
    assert_equal "21498732891470982137", secondSessionKey
    assert_not_equal secondSessionKey, firstSessionKey, "Should have a new session key"
    
    # third (invalid) request
    RFacebook::FacebookWebSession.any_instance.expects(:call_method).raises(RFacebook::FacebookSession::RemoteStandardError)
    post :index, {:auth_token => "ijklmnop"}
    assert @controller.fbsession.is_ready?
    assert_equal "viewing index", @response.body
    
    thirdSessionKey = @controller.fbsession.session_key
    assert_equal thirdSessionKey, secondSessionKey, "Session key should be unchanged"
    
  end
  
  def test_should_have_empty_fbparams_when_signature_is_invalid
    post :nofilter, {:fb_sig_session_key => "12345", :fb_sig => "invalidsignature123"}
    assert (!@controller.fbparams or @controller.fbparams.size == 0)
  end
  
  def test_should_rewrite_urls_when_in_canvas
    @controller.simulate_inside_canvas
    post :render_foobar_action_on_callback
    assert @controller.in_facebook_canvas?, "Should be in canvas for rewriting to happen"
    assert_equal "http://apps.facebook.com#{@controller.facebook_canvas_path}foobar", @response.body
  end
  
  def test_should_not_rewrite_urls_when_outside_canvas
    post :render_foobar_action_on_callback
    assert !@controller.in_facebook_canvas?, "Should not be in canvas"
    assert_equal "#{@controller.facebook_callback_path}foobar", @response.body
  end




  
  
  def setup
    @controller = DummyController.new
    @request    = ActionController::TestRequest.new
    @response   = ActionController::TestResponse.new
    
    @dummy_auth_getSession_response1 = <<-EOF
      <?xml version="1.0" encoding="UTF-8"?>
      <auth_getSession_response
        xmlns="http://api.facebook.com/1.0/"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:schemaLocation="http://api.facebook.com/1.0/ http://api.facebook.com/1.0/facebook.xsd">
          <session_key>5f34e11bfb97c762e439e6a5-8055</session_key>
          <uid>8055</uid>
          <expires>1173309298</expires>
      </auth_getSession_response>
    EOF
    
    @dummy_auth_getSession_response2 = <<-EOF
      <?xml version="1.0" encoding="UTF-8"?>
      <auth_getSession_response
        xmlns="http://api.facebook.com/1.0/"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:schemaLocation="http://api.facebook.com/1.0/ http://api.facebook.com/1.0/facebook.xsd">
          <session_key>21498732891470982137</session_key>
          <uid>8055</uid>
          <expires>1173309298</expires>
      </auth_getSession_response>
    EOF
    
  end
    
end
