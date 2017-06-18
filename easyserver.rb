require 'sinatra'
require 'boxr'
require 'redis'
require 'rest-client'
require 'hashie'
require 'json'
require 'exif'
require 'open-uri'
require 'Launchy'

use Rack::Session::Cookie, :key => 'SESSION_ID',
                           :expire_after => 60,
                           :secret => Digest::SHA256.hexdigest(rand.to_s)

before do   # Before every request, make sure they get assigned an ID.
    session[:id] ||= SecureRandom.uuid
end

  $r = Redis.new
def gettoken(code)
    
   # $r = Redis.new
    res = RestClient.post('https://api.box.com/oauth2/token', {grant_type: 'authorization_code', code: code, client_id: 'xxx', client_secret: 'xxxx'})
    parsed = JSON.parse(res.body)
  #  atoken = parsed["access_token"]
 #   rtoken = parsed["refresh_token"]
#    userid = Boxr::Client.new(parsed["access_token"]).me.id
    
#$r.set("userid:#{userid}",'{"atoken":'"#{atoken},"'"rtoken":'"#{rtoken}}")
    
    $r.set("rtoken", parsed["refresh_token"])
    $r.set("atoken",parsed["access_token"])
    
    begin
    rescue Exception => e
        return e.message
    end
    return "success! + #{$r.get('atoken')}"
   
end


def storeSession()
   


end

def refreshPair
    redis = Redis.new

    atoken = redis.get("atoken")
    rtoken = redis.get("rtoken")

    rt = Boxr::refresh_tokens(rtoken, client_id: 'xxx',client_secret: 'xxx')
    redis.set("rtoken",rt.refresh_token)
    redis.set("atoken",rt.access_token)
    redis.save
    atoken = redis.get("aoken")
    return atoken
end

def updatedesc(fileid)
         atoken = $r.get("atoken")
         client =  Boxr::Client.new(atoken)
        dlphoto = client.download_url(fileid, version: nil)
begin
payload = {url: dlphoto}
r = RestClient.post 'https://westus.api.cognitive.microsoft.com/vision/v1.0/describe?maxCandidates=1', payload.to_json,headers={"content_type": "json","Ocp-Apim-Subscription-Key": "xxx"}
hash = JSON.parse r.body
obj = Hashie::Mash.new hash
desc = obj.description.captions[0].text
client.update_file(fileid,description: desc.to_s)
rescue
end
return "success"
    end

def updateMetada(fileid)
        atoken = $r.get("atoken")
        client =  Boxr::Client.new(atoken)
        dlphoto = client.download_url(fileid, version: nil)
        payload = {url: dlphoto}
        r = RestClient.post 'https://westus.api.cognitive.microsoft.com/vision/v1.0/describe?maxCandidates=1', 
        payload.to_json,headers={"content_type": "json","Ocp-Apim-Subscription-Key": "xxx"}
        hash = JSON.parse r.body
        obj = Hashie::Mash.new hash
        tags = obj.description
        meta = {}
        i = 1
        tags.tags.each {|tag|
        meta["tag#{i}"] = tag
        i += 1
    }
    obj.metadata.each {|name, resolution|
    
        meta["#{name}"] = resolution.to_s
    }
     
        client.create_metadata(fileid,meta)
        return "success!"
    end

def getExif(filePath)
         exifdata = Exif::Data.new(filePath)
         metadata = {}
         metadata["maker"] = exifdata[:make].to_s
         metadata["model"] = exifdata[:model].to_s
         metadata["fnumber"] = exifdata[:fnumber].to_s
         metadata["pixelxdimension"] = exifdata[:pixel_x_dimension].to_s
         metadata["pixelydimension"] = exifdata[:pixel_y_dimension].to_s
         metadata["gpslatitude"] = exifdata[:gps_latitude].to_s
         metadata["gpsaltitude"] = exifdata[:gps_longitude].to_s
        
         return metadata
end




before do   # Before every request, make sure they get assigned an ID.
    session[:id] ||= SecureRandom.uuid
end


def authUser(username)
    $r.find(username)
end


def changelang(lang)
    a = $r.get("atoken")
    client = Boxr::Client.new(a)
    user = client.me.id
    client.update_user(user, language: lang)
end

def fileinfo(fileid)
    a = $r.get("atoken")
    client = Boxr::Client.new(a)
    file = client.file_from_id(fileid)
    return file.name
end


get '/' do
     @hello = "daichi"
     return erb :index

    end

post '/describe_photo' do
fileid = params[:fileid]
updatedesc(fileid)

end

post '/updateMeta' do
fileid = params[:fileid]
updateMetada(fileid)
    end 


get '/oauth' do
    code = params[:code]
    gettoken(code)
end

get '/token' do
     begin
         atoken = $r.get("atoken")
         client =  Boxr::Client.new(atoken)
         @token = atoken
         erb :showtoken
     rescue
         @token = refreshPair
         erb :showtoken
     end

     end

get '/authenticate' do
    Launchy.open("https://account.box.com/api/oauth2/authorize?response_type=code&client_id=xxx&redirect_uri=http://localhost:4567/oauth&state=xxx")
end

get '/upload' do
    puts "uploading files..."
    atoken = $r.get("atoken")

client = Boxr::Client.new(atoken)
folder = client.folder_from_id(0)
file = client.upload_file('test.txt', folder)
file.id
sleep(5)
client.upload_new_version_of_file('test.txt',file.id)
end

post '/docAuth' do
    code = params[:code]
    end

post '/postexif' do
    fileid = params[:fileid]
    atoken = $r.get("atoken")
    client =  Boxr::Client.new(atoken)
    dlphoto = client.download_url(fileid, version: nil)
    
    fileName = "hello.jpeg"
    dirName = "./tmp/photo/"
    filePath = dirName + fileName

    # create folder if not exist
    FileUtils.mkdir_p(dirName) unless FileTest.exist?(dirName)

    # write image adata
    open(filePath, 'wb') do |output|
    open(dlphoto) do |data|
    output.write(data.read)
        end
    end
    
    metadata = getExif(filePath) 
    client.create_metadata(fileid,metadata,scope: :enterprise, template: :exifdata)
    #File.delete(filePath)
    
    return dlphoto

end

post '/convert2pdf-test' do
    fileid = params[:fileid]
    atoken = $r.get("atoken")
    client = Boxr::Client.new(atoken)
begin
    res = RestClient.get("https://api.box.com/2.0/files/#{fileid}/preview.pdf", {Authorization: "Bearer #{atoken}"})
    boxfile = client.file_from_id(fileid).name
    filename = File.basename(boxfile,'.*')
    filePath = "./#{filename}.pdf"
    File.open(filePath, 'wb'){
    |file| file.write(res.body)
    }
    client.upload_new_version_of_file(filePath,fileid)
    client.update_file(fileid, name: "#{filename}"+".pdf")
    return "uploaded pdf"
    File.delete(filePath)
rescue
    

    end
end

post 'annotations' do
    fileid = params[:fileid]
    atoken = $r.get("atoken")
    client =  Boxr::Client.new(atoken)
    file = client.embed_url(fileid,show_annotations:true)
    Launchy.open(file);
end



post '/documentLinking' do
    fileid = params[:fileid]
    atoken

end

get '/locale' do
    return erb :language


end

post '/updatelang' do
@lang = params[:lang]
    begin
        changelang(@lang)
    rescue Exception => e
        refreshPair
        changelang(@lang)
    end
    return "updated locale #{@lang}"

end

get '/home' do
    @cookie = session[:id]
    
    return erb :home
end

post '/initsfc' do
    @fileid = params[:fileid]
    @collab = params[:collab]
    @email = params[:email]
    
end

post '/invite2file' do

end

get '/ocr' do
   fileid = params[:fileid]
   atoken = $r.get("atoken")
        sentence = []
        client =  Boxr::Client.new(atoken)
        dlphoto = client.download_url(fileid, version: nil)
        payload = {url: dlphoto}
        r = RestClient.post 'https://westus.api.cognitive.microsoft.com/vision/v1.0/ocr?language=unk&detectOrientation=true', 
        payload.to_json,headers={"content_type": "application/json","Ocp-Apim-Subscription-Key": "xxx"}
        hash = JSON.parse r.body
        obj = Hashie::Mash.new hash
        obj.regions.each {|a| a.lines.each {|b| b.words.each {|c| sentence.push(c.text)}}}
        if sentence.size > 0 then
        client.add_comment_to_file(fileid,message: sentence.join, tagged_message: nil)
        end
       updatedesc(fileid)
        return "success!"
  
end

post '/ocr' do
   fileid = params[:fileid]
   atoken = $r.get("atoken")
        sentence = []
        client =  Boxr::Client.new(atoken)
        dlphoto = client.download_url(fileid, version: nil)
        payload = {url: dlphoto}
        r = RestClient.post 'https://westus.api.cognitive.microsoft.com/vision/v1.0/ocr?language=unk&detectOrientation=true', 
        payload.to_json,headers={"content_type": "application/json","Ocp-Apim-Subscription-Key": "xxx"}
        hash = JSON.parse r.body
        obj = Hashie::Mash.new hash
        obj.regions.each {|a| a.lines.each {|b| b.words.each {|c| sentence.push(c.text)}}}
     
        client.add_comment_to_file(fileid,message: sentence.join, tagged_message: nil)
        return "success!"
end

get '/strash' do
    return erb :search_trash

end

get '/widget' do
    return erb :widget
end

post '/age' do
      fileid = params[:fileid]
   atoken = $r.get("atoken")
        sentence = []
        client =  Boxr::Client.new(atoken)
        dlphoto = client.download_url(fileid, version: nil)
        payload = {url: dlphoto}
        r = RestClient.post 'https://westus.api.cognitive.microsoft.com/face/v1.0/detect&returnFaceAttributes', 
        payload.to_json,headers={"content_type": "application/json","Ocp-Apim-Subscription-Key": "xxx"}
        hash = JSON.parse r.body
        obj = Hashie::Mash.new hash

end 
