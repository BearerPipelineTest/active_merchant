require 'test_helper'

class RemotePlexoTest < Test::Unit::TestCase
  def setup
    @gateway = PlexoGateway.new(fixtures(:plexo))

    @amount = 100
    @credit_card = credit_card('5555555555554444', month: '12', year: '2024', verification_value: '111', first_name: 'Santiago', last_name: 'Navatta')
    @declined_card = credit_card('5555555555554445')
    @options = {
      email: 'snavatta@plexo.com.uy',
      ip: '127.0.0.1',
      items: [
        {
          name: 'prueba',
          description: 'prueba desc',
          quantity: '1',
          price: '100',
          discount: '0'
        }
      ],
      amount_details: {
        tip_amount: '5'
      },
      identification_type: '1',
      identification_value: '123456',
      billing_address: address
    }

    @cancel_options = {
      description: 'Test desc',
      reason: 'requested by client'
    }
  end

  def test_successful_purchase
    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
  end

  def test_failed_purchase
    response = @gateway.purchase(@amount, @declined_card, @options)
    assert_failure response
    assert_equal 'denied', response.params['status']
    assert_equal '10', response.error_code
  end

  def test_successful_authorize_with_metadata
    meta = {
      custom_one: 'my field 1'
    }
    auth = @gateway.authorize(@amount, @credit_card, @options.merge({ metadata: meta }))
    assert_success auth

    assert capture = @gateway.capture(@amount, auth.authorization)
    assert_success capture
  end

  def test_successful_authorize_and_capture
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    assert capture = @gateway.capture(@amount, auth.authorization)
    assert_success capture
  end

  def test_failed_authorize
    response = @gateway.authorize(@amount, @declined_card, @options)
    assert_failure response
    assert_equal '10', response.error_code
    assert_equal 'denied', response.params['status']
  end

  def test_partial_capture
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    assert capture = @gateway.capture(@amount - 1, auth.authorization)
    assert_success capture
  end

  def test_failed_capture
    response = @gateway.capture(@amount, '123')
    assert_failure response
    assert_equal 'An internal error occurred. Contact support.', response.message
  end

  def test_successful_refund
    purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase

    assert refund = @gateway.refund(@amount, purchase.authorization, @cancel_options)
    assert_success refund
  end

  def test_partial_refund
    purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase

    assert refund = @gateway.refund(@amount - 1, purchase.authorization, @cancel_options.merge({ type: 'partial-refund' }))
    assert_success refund
  end

  def test_failed_refund
    response = @gateway.refund(@amount, '123', @cancel_options)
    assert_failure response
    assert_equal 'An internal error occurred. Contact support.', response.message
  end

  def test_successful_void
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    assert void = @gateway.void(auth.authorization, @cancel_options)
    assert_success void
  end

  def test_failed_void
    response = @gateway.void('123', @cancel_options)
    assert_failure response
    assert_equal 'An internal error occurred. Contact support.', response.message
  end

  def test_successful_verify
    response = @gateway.verify(@credit_card, @options)
    assert_success response
  end

  def test_successful_verify_with_custom_amount
    response = @gateway.verify(@credit_card, @options.merge({ verify_amount: '400' }))
    assert_success response
  end

  def test_failed_verify
    response = @gateway.verify(@declined_card, @options)
    assert_failure response
    assert_equal 400, response.error_code
  end

  def test_invalid_login
    gateway = PlexoGateway.new(client_id: '', api_key: '')

    response = gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
  end

  def test_transcript_scrubbing
    transcript = capture_transcript(@gateway) do
      @gateway.purchase(@amount, @credit_card, @options)
    end
    transcript = @gateway.scrub(transcript)

    assert_scrubbed(@credit_card.number, transcript)
    assert_scrubbed(@gateway.options[:api_key], transcript)
  end
end
