module Concerns
	module PointLineItemExpiring
		extend ActiveSupport::Concern
		
		module ClassMethods
			
			def points_available? pli
				plis  = plis_after pli
				decide_availability plis
			end

			def points_until_expired pli
			    plis = plis_up_to pli
			    sum_until_expired plis
			end

			def redeem_points pli
				plis = plis_after pli
		        redeem plis
			end

			def latest_pli_of user, input_date
		   	  date = input_date.to_date
		      where("created_at < ?", date + 1.day).
			  where("points > 0 and user_id = ? ", user.id).
			  order("created_at desc").first
			end

			def expire(user, input_date)
				date = input_date.to_date - 1.year
				latest_pli = latest_pli_of user, date
				if !latest_pli.expired && points_available?(latest_pli) 
					points_to_expire = points_until_expired(latest_pli). 
					                   + redeem_points(latest_pli)
		            expire_points  points_to_expire, latest_pli
		            flush_caches latest_pli
		        end
			end
	  	    
	  	    def expire_points  points_to_expire, pli
			 	PointLineItem.create(user_id: pli.user_id, points: -points_to_expire,
					source: expire_source(pli), expired: true)
				pli.update_attribute(:expired, true)
				expire_redeems  pli
			end

			private 

			  def flush_caches pli
			  	Rails.cache.delete(["point_line_items","after",pli.id])
			  	Rails.cache.delete(["point_line_items", "up to",pli.id])
			  end



			  def plis_after pli
			  	Rails.cache.fetch(["point_line_items","after",pli.id]) do 
			  	  where("user_id = ? and created_at > ?", pli.user_id, pli.created_at).to_a
			    end
			  end

			  def plis_up_to pli
			  	Rails.cache.fetch(["point_line_items", "up to",pli.id]) do
					where("user_id = ? and created_at <= ?",pli.user_id, pli.created_at).
					order("created_at desc").to_a
				end
			  end

			  def decide_availability plis
			  	previous = plis.first
			  	plis.each do |pli|
			  		return false unless available? previous, pli, binding
			    end
			    return true
			  end


			  def available?  previous, pli, bndg
			  	 if pli.points < 0 && pli.expired
			  		return true # do nothing
			  	 elsif (previous.points > 0 && pli.points < 0) ||
			  		   (pli.points > 0 && pli.expired)
			  		return false
		  		 else 
		  		    eval "previous = pli", bndg
			     end     
			  end 

			  def sum_until_expired plis
			  	sum = 0
			  	plis.each do |pli|
			  		break unless can_add_to? pli, binding
		    	end
		    	return sum
			  end

			  def can_add_to? pli, bndg
			  	 if pli.points > 0 && pli.expired
			  		false
			  	 elsif !(pli.points < 0 && pli.expired)
			    	eval "sum += pli.points", bndg
			     else
			     	true
			     end
			  end

			  def redeem plis
			  	points = 0
		   		plis.each  do |pli|
		   			break unless can_redeem? pli, binding
		   		end
		   		return points
			  end

			  def can_redeem? pli, bndg
			  	 if pli.points > 0
			  	 	false
			  	 elsif !pli.expired
			  	 	eval "points += pli.points", bndg
			  	 else
			  	 	true
			  	 end	 
			  end


			  def expire_redeems pli
			  	plis = plis_after pli
			  	plis.each  do |pli|
		   		   break if pli.points > 0
				   pli.update_attribute(:expired, true)
		   		end
			  end

			  def expire_source pli
			  	plis_hash = prepare_plis_list pli
			  	ids  = expired_id_list  plis_hash
			  	generate_source_text ids
			  end

			  def prepare_plis_list pli
				after = plis_after pli 
				up_to = filter_until_expired plis_up_to(pli)
				{after: after, up_to: up_to}
			  end

			  def filter_until_expired plis
			    arr = [plis.first]
			    plis.each do |pli|
			    	break if pli.expired && pli.points > 0
			    	arr << pli unless arr.include?(pli)
			    end
			    return arr
			  end

			  def expired_id_list  plis_hash
			  	ids = []
			  	populate_ids plis_hash, ids
			  	return ids 
			  end

			  def populate_ids plis_hash, ids
			  	up_to = plis_hash[:up_to] 
			  	@date = up_to.first.created_at.midnight
			  	up_to.each do |pli|
			  		index = get_index up_to,  @date
			  		break if index.nil? || !added_to_id_list?(ids, index, plis_hash, binding)
			  	end	 
			  end

			  def get_index up_to, date 
			  	up_to.index {|x| x.created_at < (date + 1.day) && x.points > 0 }
			  end

			  def prepare_subarray index, plis_hash
			  	arr  = plis_hash[:up_to].reverse + plis_hash[:after]
			  	indx = plis_hash[:up_to].length-1-index
			  	arr[indx+1..-1]
			  end


			  def added_to_id_list? ids, index, plis_hash, bndg
			  	local_pli = plis_hash[:up_to][index]
			  	plis = prepare_subarray index, plis_hash
			    return false if !decide_availability plis
                ids.unshift local_pli.id unless ids.include?(local_pli.id)
			  	@date = local_pli.created_at - 1.day
			  end


			  def generate_source_text ids
			  	 source = "Points "
			  	 ids.each_with_index do |id ,index|
			  	 	source += ", " unless index == 0
			  	 	source += "##{id}"
			  	 end
			  	 source += " expired"
			  end
		end
		
		module InstanceMethods
			
		end
		
	end
end