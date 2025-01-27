require 'test_helper'

class MerchantESolutionsTest < Test::Unit::TestCase
  include CommStub

  def setup
    Base.mode = :test

    @gateway = MerchantESolutionsGateway.new(
      login: 'login',
      password: 'password'
    )

    @credit_card = credit_card
    @amount = 100

    @options = {
      order_id: '1',
      billing_address: address,
      description: 'Store Purchase'
    }
  end

  def test_successful_purchase
    @gateway.expects(:ssl_post).returns(successful_purchase_response)
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_instance_of Response, response
    assert_success response
    assert_equal '5547cc97dae23ea6ad1a4abd33445c91', response.authorization
    assert response.test?
  end

  def test_successful_purchase_with_moto_ecommerce_ind
    stub_comms(@gateway, :ssl_request) do
      @gateway.purchase(@amount, @credit_card, { moto_ecommerce_ind: '7' })
    end.check_request do |_method, _endpoint, data, _headers|
      assert_match(/moto_ecommerce_ind=7/, data)
    end.respond_with(successful_purchase_response)
  end

  def test_unsuccessful_purchase
    @gateway.expects(:ssl_post).returns(failed_purchase_response)
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert response.test?
  end

  def test_purchase_with_long_order_id_truncates_id
    options = { order_id: 'thisislongerthan17characters' }
    @gateway.expects(:ssl_post).with(
      anything,
      all_of(
        includes('invoice_number=thisislongerthan1')
      )
    ).returns(successful_purchase_response)
    assert response = @gateway.purchase(@amount, @credit_card, options)
    assert_success response
    assert_equal 'This transaction has been approved', response.message
  end

  def test_authorization
    @gateway.expects(:ssl_post).returns(successful_authorization_response)
    assert response = @gateway.authorize(@amount, @credit_card, @options)
    assert response.success?
    assert_equal '42e52603e4c83a55890fbbcfb92b8de1', response.authorization
    assert response.test?
  end

  def test_capture
    @gateway.expects(:ssl_post).returns(successful_capture_response)
    assert response = @gateway.capture(@amount, '42e52603e4c83a55890fbbcfb92b8de1', @options)
    assert response.success?
    assert_equal '42e52603e4c83a55890fbbcfb92b8de1', response.authorization
    assert response.test?
  end

  def test_refund
    @gateway.expects(:ssl_post).returns(successful_refund_response)
    assert_success @gateway.refund(@amount, '0a5ca4662ac034a59595acb61e8da025', @options)
  end

  def test_credit
    @gateway.expects(:ssl_post).returns(successful_refund_response)
    assert_success @gateway.credit(@amount, @credit_card, @options)
  end

  def test_void
    @gateway.expects(:ssl_post).returns(successful_void_response)
    assert response = @gateway.void('42e52603e4c83a55890fbbcfb92b8de1')
    assert response.success?
    assert_equal '1b08845c6dee3fa1a73fee2a009d33a7', response.authorization
    assert response.test?
  end

  def test_unstore
    @gateway.expects(:ssl_post).returns(successful_unstore_response)
    assert response = @gateway.unstore('ae641b57b19b3bb89faab44191479872')
    assert response.success?
    assert_equal 'd79410c91b4b31ba99f5a90558565df9', response.authorization
    assert response.test?
  end

  def test_successful_verify
    response = stub_comms(@gateway, :ssl_request) do
      @gateway.verify(@credit_card, { store_card: 'y' })
    end.check_request do |_method, _endpoint, data, _headers|
      assert_match(/transaction_type=A/, data)
      assert_match(/store_card=y/, data)
      assert_match(/card_number=#{@credit_card.number}/, data)
    end.respond_with(successful_verify_response)
    assert_success response
    assert_equal 'Card Ok', response.message
  end

  def test_successful_avs_check
    @gateway.expects(:ssl_post).returns(successful_purchase_response + '&avs_result=Y')
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_equal response.avs_result['code'], 'Y'
    assert_equal response.avs_result['message'], 'Street address and 5-digit postal code match.'
    assert_equal response.avs_result['street_match'], 'Y'
    assert_equal response.avs_result['postal_match'], 'Y'
  end

  def test_unsuccessful_avs_check_with_bad_street_address
    @gateway.expects(:ssl_post).returns(successful_purchase_response + '&avs_result=Z')
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_equal response.avs_result['code'], 'Z'
    assert_equal response.avs_result['message'], 'Street address does not match, but 5-digit postal code matches.'
    assert_equal response.avs_result['street_match'], 'N'
    assert_equal response.avs_result['postal_match'], 'Y'
  end

  def test_unsuccessful_avs_check_with_bad_zip
    @gateway.expects(:ssl_post).returns(successful_purchase_response + '&avs_result=A')
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_equal response.avs_result['code'], 'A'
    assert_equal response.avs_result['message'], 'Street address matches, but postal code does not match.'
    assert_equal response.avs_result['street_match'], 'Y'
    assert_equal response.avs_result['postal_match'], 'N'
  end

  def test_successful_cvv_check
    @gateway.expects(:ssl_post).returns(successful_purchase_response + '&cvv2_result=M')
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_equal response.cvv_result['code'], 'M'
    assert_equal response.cvv_result['message'], 'CVV matches'
  end

  def test_unsuccessful_cvv_check
    @gateway.expects(:ssl_post).returns(failed_purchase_response + '&cvv2_result=N')
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_equal response.cvv_result['code'], 'N'
    assert_equal response.cvv_result['message'], 'CVV does not match'
  end

  def test_visa_3dsecure_params_submitted
    stub_comms(@gateway, :ssl_request) do
      @gateway.purchase(@amount, @credit_card, @options.merge({ xid: '1', cavv: '2' }))
    end.check_request do |_method, _endpoint, data, _headers|
      assert_match(/xid=1/, data)
      assert_match(/cavv=2/, data)
    end.respond_with(successful_purchase_response)
  end

  def test_mastercard_3dsecure_params_submitted
    stub_comms(@gateway, :ssl_request) do
      @gateway.purchase(@amount, @credit_card, @options.merge({ ucaf_collection_ind: '1', ucaf_auth_data: '2' }))
    end.check_request do |_method, _endpoint, data, _headers|
      assert_match(/ucaf_collection_ind=1/, data)
      assert_match(/ucaf_auth_data=2/, data)
    end.respond_with(successful_purchase_response)
  end

  def test_supported_countries
    assert_equal ['US'], MerchantESolutionsGateway.supported_countries
  end

  def test_supported_card_types
    assert_equal %i[visa master american_express discover jcb], MerchantESolutionsGateway.supported_cardtypes
  end

  def test_scrub
    assert @gateway.supports_scrubbing?
    assert_equal @gateway.scrub(pre_scrubbed), post_scrubbed
  end

  private

  def successful_purchase_response
    'transaction_id=5547cc97dae23ea6ad1a4abd33445c91&error_code=000&auth_response_text=Exact Match&auth_code=12345A'
  end

  def successful_authorization_response
    'transaction_id=42e52603e4c83a55890fbbcfb92b8de1&error_code=000&auth_response_text=Exact Match&auth_code=12345A'
  end

  def successful_refund_response
    'transaction_id=0a5ca4662ac034a59595acb61e8da025&error_code=000&auth_response_text=Credit Approved'
  end

  def successful_void_response
    'transaction_id=1b08845c6dee3fa1a73fee2a009d33a7&error_code=000&auth_response_text=Void Request Accepted'
  end

  def successful_capture_response
    'transaction_id=42e52603e4c83a55890fbbcfb92b8de1&error_code=000&auth_response_text=Settle Request Accepted'
  end

  def successful_store_response
    'transaction_id=ae641b57b19b3bb89faab44191479872&error_code=000&auth_response_text=Card Data Stored'
  end

  def successful_unstore_response
    'transaction_id=d79410c91b4b31ba99f5a90558565df9&error_code=000&auth_response_text=Stored Card Data Deleted'
  end

  def successful_verify_response
    'transaction_id=a5ef059bff7a3f75ac2398eea4cc73cd&error_code=085&auth_response_text=Card Ok&avs_result=0&cvv2_result=M&auth_code=T1933H'
  end

  def failed_purchase_response
    'transaction_id=error&error_code=101&auth_response_text=Invalid%20I%20or%20Key%20Incomplete%20Request'
  end

  def pre_scrubbed
    <<-TRANSCRIPT
    "profile_id=94100010518900000029&profile_key=YvKeIpxLxpJoKRKkJjMOpqmGkwUCBBEO&transaction_type=D&invoice_number=123&card_number=4111111111111111&cvv2=123&card_exp_date=0919&cardholder_street_address=123%2BState%2BStreet&cardholder_zip=55555&transaction_amount=1.00"
    "transaction_id=3dfdc828adf032d589111ff45a7087fc&error_code=000&auth_response_text=Exact Match&avs_result=Y&cvv2_result=M&auth_code=T4797H"
    TRANSCRIPT
  end

  def post_scrubbed
    <<-TRANSCRIPT
    "profile_id=94100010518900000029&profile_key=[FILTERED]&transaction_type=D&invoice_number=123&card_number=[FILTERED]&cvv2=[FILTERED]&card_exp_date=0919&cardholder_street_address=123%2BState%2BStreet&cardholder_zip=55555&transaction_amount=1.00"
    "transaction_id=3dfdc828adf032d589111ff45a7087fc&error_code=000&auth_response_text=Exact Match&avs_result=Y&cvv2_result=M&auth_code=T4797H"
    TRANSCRIPT
  end
end
