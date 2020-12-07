require 'sucker_punch'
require 'sinatra'
# require 'mongoid'
require 'sinatra/json'
# require_relative 'model\Orders.rb'
require 'json'
# require_relative 'jobs\deliver.rb'
require 'rest-client'
require 'securerandom'
require 'mongoid'
require 'event_bus'
require 'bunny'

connection = Bunny.new("amqp://guest:guest@rabbitmq-service:5672")
connection.start

set :bind, '0.0.0.0'
set :port, ENV["PORT"]

Mongoid.load!(File.join(File.dirname(__FILE__), 'config', 'mongoid.yml'))
channel = connection.create_channel
queue = channel.queue('authorize_payment', :durable => false)

queue.subscribe do |_delivery_info, _properties, body|
  data = body.split("+")
  payment_status = data[1]
  card_number = data[0]
  order = Orders.find_by(card_number: card_number)
  order.payment_status = payment_status
  order.save
end

SERVICE_ID = SecureRandom.hex

TASK_LIMIT = 8

GATEWAY_ADRESS = "http://apigatewaypad:80/"

begin
  at_exit do
    RestClient.post GATEWAY_ADRESS + "services/deregister", '{ "name": "order-service", "address": "order-service:8000" }', :content_type => "application/json"
  end
rescue
  puts "Error when exit"
ensure
  puts " "
end

begin
  RestClient.post GATEWAY_ADRESS + "services", '{ "name": "order-service", "address": "order-service:8000" }', :content_type => "application/json"
rescue
  puts "Connection to the gateway failed"
ensure
  puts " "
end

  get '/healthcheck' do
    status 200
    body '200 OK'  
  end

  get '/' do
    respone =  RestClient.put GATEWAY_ADRESS + "register?replace-existing-checks=true", {"ID": SERVICE_ID, "Name": "orders-service","Address": "orders-service","Port": 8000}.to_json
    json(respone)
  end

  get '/orders' do
    Orders.all.to_json
  end

  get '/orders/:id' do #gets a specific order 
    order_id = params['id']
    order = Orders.find(order_id)
    json(order)
  end

  post '/orders' do #create a new order based on request, if the task limit isn't reached
    body = JSON.parse(request.body.read)
    order = Orders.create(type:body["type"], status:"ordered", price:body["price"], card_number:body["card_number"], payment_status:"waiting")
    json(order)
  end

  put '/orders/:id' do #the order is started and based on Orders type the time for preparation is calculated
    order_id = params["id"]
    order = Orders.find(order_id)
    order.status = "starting"
    order.save
    
    #incep comanda
    Deliver.perform_in(time_for_preparation(order.type),{id:order_id})
    json(order)

    #fac publish la datele de care Vera are nevoie
    channel = connection.create_channel
    queue = channel.queue('order_created')
    message = "#{order.card_number}+#{order.price}"
    channel.default_exchange.publish(message, routing_key: 'order_created')  
  end

  get '/status' do #gets all teh orders that are being processed
    count = Orders.all.to_a.count{|order|["ordered","starting"].include?(order.status)}
    json({count:count})
  end


  def time_for_preparation (type)
    if type == "americano" 
      return 15 
    elsif type == "espresso"
      return 3
    elsif type == "latte"
      return 7
    else return 40
    end
  end


  class Deliver
    include SuckerPunch::Job
    workers 10
  
    def perform(params)
        order = Orders.find(params[:id])
        # puts order.status
        order.status = "done"
        order.save
    end
  end

  class Orders
    include Mongoid::Document

    field :type, type: String 
    field :status, type: String
    field :price, type: Integer
    field :card_number, type: String
    field :payment_status, type: String

  end

  
 

  