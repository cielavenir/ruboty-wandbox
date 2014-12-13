#coding:utf-8
require 'json'
require 'net/http'
require 'uri'
require 'open-uri'

#クラス変数を使いたいので、Actionを切り出すことは不可能
module Ruboty
	module Handlers
		class Wandbox < Base
			def initialize(*__reserved__)
				super
				@base_uri=ENV['WANDBOX_BASE']&&!ENV['WANDBOX_BASE'].empty? ? ENV['WANDBOX_BASE'] : 'http://melpon.org/wandbox/'
				@base_uri+='/' if !@base_uri.end_with?('/')
				@input=nil
				@current_submission=nil

				@compiler_list=nil
			end
			def get_compiler_list
				@compiler_list ||= lambda{
					lst=JSON.parse Net::HTTP.get URI.parse @base_uri+'api/list.json'
					Hash[*lst.flat_map{|e|
						[e['name'],e['switches'].flat_map{|f|(f['options']||[]).map{|g|g['name']}}]
					}]
				}.call
			end
			def read_uri(uri)
				return nil if !uri||uri.empty?
				Kernel.open(uri){|f|
					return f.read
				}
			end
			def process(result)
				#fixme
				result['program_output']
			end

			on /wandbox list/, name: 'languages', description: 'show compiler list'
			on /wandbox setinput ?(?<input_uri>\S*)/, name: 'setinput', description: 'set input'
			on /wandbox submit (?<language>\S+) (?<source_uri>\S+) ?(?<input_uri>\S*)/, name: 'submit', description: 'send code via uri'
			on /ideone view ?(?<id>\w*)/, name: 'view', description: 'view submission'
			def languages(message)
				message.reply get_compiler_list.map{|k,v|k+': '+v*','+"\n"}.join
			end
			def setinput(message)
				#input_uri: 入力ファイル(空文字列ならクリア)
				if !message[:input_uri]||message[:input_uri].empty?
					@input=nil
					message.reply 'Input cleared.'
				else
					@input=read_uri(message[:input_uri])
					message.reply 'Input set.'
				end
			end
			def submit(message)
				#language: コンパイラID,オプションID(カンマ区切り)。それぞれ完全一致でなければならない。
				#source_uri: ソースファイル
				#input_uri: 入力ファイル(空文字列ならsetinputの内容を使用)
				input=message[:input_uri]&&!message[:input_uri].empty? ? read_uri(message[:input_uri]) : @input

				options=message[:language].split(',')
				lang=options.shift
				options=get_compiler_list[lang]
				if !options || options.any?{|opt|compiler['switches'].none?{|e|e['name']==opt}}
					message.reply '[Ruboty::Wandbox] invalid compiler name'
				end
				json={
					compiler: lang,
					code: read_uri(message[:source_uri]),
					options: options*',',
					stdin: input,
					save: false, #fixme
				}
				uri=URI.parse(@base_uri+'api/compile.json')
				Net::HTTP.start(uri.host,uri.port){|http|
					resp=http.post(uri.path,JSON.generate(json),{
						'Content-Type'=>'application/json',
					})
					p JSON.parse(resp.body)
					message.reply process(JSON.parse(resp.body))
				}
			end
			def view(message)
				#id: wandbox ID(空文字列なら直前のsubmitで返されたIDを使用)
				submission=message[:id]&&!message[:id].empty? ? message[:id] : @current_submission
				resp=JSON.parse Net::HTTP.get URI.parse @base_uri+'api/permlink/'+submission
				message.reply process(resp['result'])
			end
		end
	end
end
